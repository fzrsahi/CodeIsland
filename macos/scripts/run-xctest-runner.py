#!/usr/bin/env python3
"""
Standalone XCTest Runner Harness for macOS Command Line Tools.
Discovers and executes XCTestCase suites on Darwin CLT without full Xcode.app.
"""

import os
import re
import sys
import subprocess
import argparse

def locate_frameworks_dir():
    """
    Dynamically locates the directory containing XCTest.framework.
    Supports Xcode, Command Line Tools, and environment overrides.
    Returns (frameworks_dir, checked_paths).
    """
    checked = []

    env_dir = os.environ.get("XCTEST_FRAMEWORK_DIR")
    if env_dir:
        checked.append(f"$XCTEST_FRAMEWORK_DIR ({env_dir})")
        if os.path.exists(os.path.join(env_dir, "XCTest.framework")):
            return env_dir, checked

    def check_cand(path, label):
        if not path:
            return None
        checked.append(f"{label}: {path}")
        if os.path.exists(os.path.join(path, "XCTest.framework")):
            return path
        return None

    # 1. xcrun --sdk macosx --show-sdk-platform-path
    try:
        res = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
                             capture_output=True, text=True, check=True)
        cand = os.path.join(res.stdout.strip(), "Developer", "Library", "Frameworks")
        found = check_cand(cand, "xcrun platform Developer/Library/Frameworks")
        if found:
            return found, checked
    except Exception:
        pass

    # 2. xcrun --sdk macosx --show-sdk-path
    try:
        res = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                             capture_output=True, text=True, check=True)
        cand = os.path.join(res.stdout.strip(), "Developer", "Library", "Frameworks")
        found = check_cand(cand, "xcrun sdk Developer/Library/Frameworks")
        if found:
            return found, checked
    except Exception:
        pass

    # 3. xcode-select -p
    try:
        res = subprocess.run(["xcode-select", "-p"],
                             capture_output=True, text=True, check=True)
        dev = res.stdout.strip()
        for cand in [
            os.path.join(dev, "Platforms", "MacOSX.platform", "Developer", "Library", "Frameworks"),
            os.path.join(dev, "Library", "Developer", "Frameworks")
        ]:
            found = check_cand(cand, "xcode-select candidate")
            if found:
                return found, checked
    except Exception:
        pass

    # 4. Standard static CLT & Xcode paths
    static_cands = [
        "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
        "/Applications/Xcode.app/Contents/Developer/Library/Frameworks",
    ]
    for cand in static_cands:
        found = check_cand(cand, "static candidate")
        if found:
            return found, checked

    return None, checked

def discover_tests_from_binary(binary_path, target_modules=None, filter_pattern=None):
    """
    Extracts all test methods and their signatures directly from the Mach-O binary
    symbol table via `nm` and `swift-demangle`.
    Returns dict: { (module, class_name): [(method_name, is_async, is_throws)] }
    """
    cmd = f"nm -g '{binary_path}' | xcrun swift-demangle"
    proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, text=True)
    pattern = re.compile(r'^\s*[0-9a-fA-F]+\s+T\s+([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\.(test[A-Za-z0-9_]*)\(\s*\)(?:\s+(async))?(?:\s+(throws))?\s*->\s*\(\)')
    
    tests_by_class = {}
    for line in proc.stdout:
        m = pattern.search(line)
        if not m:
            continue
        mod, cls, method, is_async, is_throws = m.groups()
        if target_modules and mod not in target_modules:
            continue
        if filter_pattern and not re.search(filter_pattern, f"{mod}.{cls}.{method}"):
            continue
        key = (mod, cls)
        tests_by_class.setdefault(key, []).append((method, bool(is_async), bool(is_throws)))
    
    proc.wait()
    return tests_by_class

def generate_runner_source(tests_by_class, output_path):
    """
    Generates RunnerMain.swift connecting all discovered test suites to XCTMain.
    """
    lines = [
        "// Generated standalone XCTest runner harness",
        "import Foundation",
        "import XCTest",
        "@testable import MorrowCore",
        "@testable import MorrowCoreTests",
        "@testable import Morrow",
        "@testable import MorrowTests",
        "",
        "@main",
        "struct RunnerMain {",
        "    static func main() {",
        "        var entries: [XCTestCaseEntry] = []",
    ]

    for (mod, cls), methods in sorted(tests_by_class.items()):
        lines.append(f"        // {mod}.{cls} ({len(methods)} tests)")
        lines.append(f"        entries.append(testCase([")
        for m, is_async, is_throws in methods:
            if is_async:
                lines.append(f'            ("{m}", {{ (tc: {cls}) in {{ () throws -> Void in')
                lines.append(f'                let exp = tc.expectation(description: "{m}")')
                if is_throws:
                    lines.append(f'                var asyncErr: Error? = nil')
                    lines.append(f'                Task {{')
                    lines.append(f'                    do {{')
                    lines.append(f'                        try await tc.{m}()')
                    lines.append(f'                    }} catch {{')
                    lines.append(f'                        asyncErr = error')
                    lines.append(f'                    }}')
                    lines.append(f'                    exp.fulfill()')
                    lines.append(f'                }}')
                    lines.append(f'                tc.waitForExpectations(timeout: 60)')
                    lines.append(f'                if let err = asyncErr {{ throw err }}')
                else:
                    lines.append(f'                Task {{')
                    lines.append(f'                    await tc.{m}()')
                    lines.append(f'                    exp.fulfill()')
                    lines.append(f'                }}')
                    lines.append(f'                tc.waitForExpectations(timeout: 60)')
                lines.append(f'            }} }}),')
            else:
                lines.append(f'            ("{m}", {cls}.{m}),')
        lines.append(f"        ]))")

    lines.extend([
        "        print(\"==> Executing XCTest harness with \(entries.count) test suites...\")",
        "        XCTMain(entries)",
        "    }",
        "}",
    ])

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

def main():
    parser = argparse.ArgumentParser(description="Standalone XCTest Runner")
    parser.add_argument("--repo-root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        help="Swift package root (default: macos/, the parent of this script's directory)")
    parser.add_argument("--target", default="all", choices=["all", "core", "app"], help="Target test suite")
    parser.add_argument("--filter", default=None, help="Regex filter for test cases")
    parser.add_argument("--skip-build", action="store_true", help="Skip swift build of test targets")
    args = parser.parse_args()

    repo_root = os.path.abspath(args.repo_root)
    build_dir = os.path.join(repo_root, ".build")

    # 1. Build test targets if not skipped
    # Pin native build system to guarantee consistent Mach-O artifacts and Objects.LinkFileList
    build_system_flags = ["--build-system", "native"]
    if not args.skip_build:
        print("==> Building test targets with SwiftPM (native build system)...")
        cmd = ["swift", "build", "--build-tests"] + build_system_flags
        res = subprocess.run(cmd, cwd=repo_root)
        if res.returncode != 0:
            print("ERROR: [Toolchain] 'swift build --build-tests --build-system native' failed.", file=sys.stderr)
            sys.exit(res.returncode)

    # Locate bin_dir via SwiftPM if available
    bin_dir = None
    try:
        res = subprocess.run(
            ["swift", "build", "--show-bin-path"] + build_system_flags,
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True
        )
        cand = res.stdout.strip()
        if os.path.isdir(cand):
            bin_dir = cand
    except Exception:
        pass

    # 2. Locate Objects.LinkFileList and test bundle binary
    linkfile = None
    bundle_bin = None
    linkfile_candidates = {}

    # Quick check in bin_dir if known
    if bin_dir:
        cand_bin = os.path.join(bin_dir, "MorrowPackageTests.xctest", "Contents", "MacOS", "MorrowPackageTests")
        if os.path.isfile(cand_bin):
            bundle_bin = cand_bin
        cand_lf = os.path.join(bin_dir, "MorrowPackageTests.build", "Objects.LinkFileList")
        if os.path.isfile(cand_lf):
            linkfile_candidates["morrow"] = cand_lf

    for root, dirs, files in os.walk(build_dir):
        if "Objects.LinkFileList" in files and "PackageTests" in root:
            if "MorrowPackageTests" in root:
                linkfile_candidates["morrow"] = os.path.join(root, "Objects.LinkFileList")
            elif "CodeIslandPackageTests" in root:
                linkfile_candidates["codeisland"] = os.path.join(root, "Objects.LinkFileList")
            else:
                linkfile_candidates.setdefault("generic", os.path.join(root, "Objects.LinkFileList"))
        if "MorrowPackageTests.xctest" in dirs:
            candidate = os.path.join(root, "MorrowPackageTests.xctest/Contents/MacOS/MorrowPackageTests")
            if os.path.isfile(candidate):
                bundle_bin = candidate
        elif "CodeIslandPackageTests.xctest" in dirs and not bundle_bin:
            candidate = os.path.join(root, "CodeIslandPackageTests.xctest/Contents/MacOS/CodeIslandPackageTests")
            if os.path.isfile(candidate):
                bundle_bin = candidate

    linkfile = linkfile_candidates.get("morrow") or linkfile_candidates.get("codeisland") or linkfile_candidates.get("generic")

    if not linkfile or not os.path.isfile(linkfile):
        print("ERROR: [Toolchain] Objects.LinkFileList not found in .build.", file=sys.stderr)
        print(f"Searched build directory: {build_dir}", file=sys.stderr)
        if bin_dir:
            print(f"SwiftPM bin directory: {bin_dir}", file=sys.stderr)
        print("Diagnosis: SwiftPM did not produce native link file list. Verify build system is native.", file=sys.stderr)
        sys.exit(1)

    if not bundle_bin or not os.path.isfile(bundle_bin):
        print("ERROR: [Toolchain] MorrowPackageTests binary not found in .build.", file=sys.stderr)
        print(f"Searched build directory: {build_dir}", file=sys.stderr)
        sys.exit(1)

    debug_dir = os.path.dirname(os.path.dirname(linkfile))
    modules_dir = os.path.join(debug_dir, "Modules")

    # Locate frameworks directory dynamically (Xcode vs CLT vs custom override)
    frameworks_dir, checked_paths = locate_frameworks_dir()
    if not frameworks_dir:
        print("ERROR: [Toolchain] Could not locate 'XCTest.framework'.", file=sys.stderr)
        print("Checked candidate paths:", file=sys.stderr)
        for p in checked_paths:
            print(f"  - {p}", file=sys.stderr)
        print("\nDiagnosis: Neither Xcode.app nor CommandLineTools with XCTest was found.", file=sys.stderr)
        print("Remedy:", file=sys.stderr)
        print("  - On developer Mac with Xcode: run 'sudo xcode-select -s /Applications/Xcode.app'", file=sys.stderr)
        print("  - On headless CLT CI runner: ensure 'scripts/setup-macos-runner.sh' has run.", file=sys.stderr)
        print("  - Or specify path manually: export XCTEST_FRAMEWORK_DIR=/path/to/Frameworks", file=sys.stderr)
        sys.exit(1)

    print(f"==> Using XCTest.framework from: {frameworks_dir}")

    # Filter object files (exclude existing synthetic runner)
    with open(linkfile, "r") as f:
        obj_files = [line.strip() for line in f if line.strip() and not line.strip().endswith("runner.swift.o")]

    # 3. Discover test methods via symbol table
    target_modules = []
    if args.target in ["all", "core"]:
        target_modules.extend(["MorrowCoreTests", "CodeIslandCoreTests"])
    if args.target in ["all", "app"]:
        target_modules.extend(["MorrowTests", "CodeIslandTests"])

    tests_by_class = discover_tests_from_binary(bundle_bin, target_modules, args.filter)
    total_classes = len(tests_by_class)
    total_methods = sum(len(m) for m in tests_by_class.values())

    print(f"==> Discovered {total_classes} test classes, {total_methods} test methods.")
    if total_methods == 0:
        print("Warning: No matching test cases found.")
        sys.exit(0)

    runner_swift = "/tmp/morrow_runner_main.swift"
    runner_bundle_dir = os.path.join(debug_dir, "MorrowCLTRunner.xctest", "Contents", "MacOS")
    os.makedirs(runner_bundle_dir, exist_ok=True)
    runner_bin = os.path.join(runner_bundle_dir, "morrow-test-runner")
    generate_runner_source(tests_by_class, runner_swift)

    # Collect include & modulemap flags for C dependencies (CYaml)
    module_flags = []
    seen_dirs = set()
    for root, _, files in os.walk(build_dir):
        if "module.modulemap" in files and "checkouts" in root:
            mpath = os.path.join(root, "module.modulemap")
            if ".framework" in mpath:
                continue
            incdir = os.path.dirname(mpath)
            if incdir not in seen_dirs:
                seen_dirs.add(incdir)
                module_flags.extend([
                    "-Xcc", f"-fmodule-map-file={mpath}",
                    "-Xcc", "-I", "-Xcc", incdir,
                    "-I", incdir
                ])

    # 4. Compile standalone test runner executable
    print(f"==> Compiling standalone test runner binary with swiftc...")
    compile_cmd = [
        "swiftc", "-parse-as-library",
        "-F", frameworks_dir,
        "-F", debug_dir,
        "-framework", "Sparkle",
        "-framework", "XCTest",
        "-I", modules_dir,
        "-Xlinker", "-rpath", "-Xlinker", frameworks_dir,
        "-Xlinker", "-rpath", "-Xlinker", debug_dir,
        "-o", runner_bin,
    ] + module_flags + obj_files + [runner_swift]

    res = subprocess.run(compile_cmd)
    if res.returncode != 0:
        print(f"ERROR: [Toolchain] swiftc failed to compile test runner (exit code {res.returncode}).", file=sys.stderr)
        print(f"Frameworks directory: {frameworks_dir}", file=sys.stderr)
        print(f"Debug products directory: {debug_dir}", file=sys.stderr)
        sys.exit(res.returncode)

    # 5. Execute the test runner
    print(f"==> Launching {runner_bin}...")
    run_env = os.environ.copy()
    run_env["XCTestConfigurationFilePath"] = "/tmp/xctest.plist"
    run_res = subprocess.run([runner_bin], env=run_env)
    sys.exit(run_res.returncode)

if __name__ == "__main__":
    main()
