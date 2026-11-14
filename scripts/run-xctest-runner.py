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
        "@testable import CodeIslandCore",
        "@testable import CodeIslandCoreTests",
        "@testable import CodeIsland",
        "@testable import CodeIslandTests",
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
    parser.add_argument("--repo-root", default=os.getcwd(), help="Repository root")
    parser.add_argument("--target", default="all", choices=["all", "core", "app"], help="Target test suite")
    parser.add_argument("--filter", default=None, help="Regex filter for test cases")
    parser.add_argument("--skip-build", action="store_true", help="Skip swift build of test targets")
    args = parser.parse_args()

    repo_root = os.path.abspath(args.repo_root)
    build_dir = os.path.join(repo_root, ".build")

    # 1. Build test targets if not skipped
    if not args.skip_build:
        print("==> Building test targets with SwiftPM...")
        cmd = ["swift", "build", "--build-tests"]
        res = subprocess.run(cmd, cwd=repo_root)
        if res.returncode != 0:
            print("ERROR: swift build --build-tests failed", file=sys.stderr)
            sys.exit(res.returncode)

    # 2. Locate Objects.LinkFileList and test bundle binary
    linkfile = None
    bundle_bin = None
    for root, dirs, files in os.walk(build_dir):
        if "Objects.LinkFileList" in files and "PackageTests" in root:
            linkfile = os.path.join(root, "Objects.LinkFileList")
        if "CodeIslandPackageTests.xctest" in dirs:
            candidate = os.path.join(root, "CodeIslandPackageTests.xctest/Contents/MacOS/CodeIslandPackageTests")
            if os.path.isfile(candidate):
                bundle_bin = candidate

    if not linkfile or not os.path.isfile(linkfile):
        print("ERROR: Objects.LinkFileList not found in .build. Run 'swift test' first.", file=sys.stderr)
        sys.exit(1)

    if not bundle_bin or not os.path.isfile(bundle_bin):
        print("ERROR: CodeIslandPackageTests binary not found in .build.", file=sys.stderr)
        sys.exit(1)

    debug_dir = os.path.dirname(os.path.dirname(linkfile))
    modules_dir = os.path.join(debug_dir, "Modules")
    frameworks_dir = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

    # Filter object files (exclude existing synthetic runner)
    with open(linkfile, "r") as f:
        obj_files = [line.strip() for line in f if line.strip() and not line.strip().endswith("runner.swift.o")]

    # 3. Discover test methods via symbol table
    target_modules = []
    if args.target in ["all", "core"]:
        target_modules.append("CodeIslandCoreTests")
    if args.target in ["all", "app"]:
        target_modules.append("CodeIslandTests")

    tests_by_class = discover_tests_from_binary(bundle_bin, target_modules, args.filter)
    total_classes = len(tests_by_class)
    total_methods = sum(len(m) for m in tests_by_class.values())

    print(f"==> Discovered {total_classes} test classes, {total_methods} test methods.")
    if total_methods == 0:
        print("Warning: No matching test cases found.")
        sys.exit(0)

    runner_swift = "/tmp/codeisland_runner_main.swift"
    runner_bundle_dir = os.path.join(debug_dir, "CodeIslandCLTRunner.xctest", "Contents", "MacOS")
    os.makedirs(runner_bundle_dir, exist_ok=True)
    runner_bin = os.path.join(runner_bundle_dir, "codeisland-test-runner")
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
        print("ERROR: Failed to compile test runner", file=sys.stderr)
        sys.exit(res.returncode)

    # 5. Execute the test runner
    print(f"==> Launching {runner_bin}...")
    run_res = subprocess.run([runner_bin])
    sys.exit(run_res.returncode)

if __name__ == "__main__":
    main()
