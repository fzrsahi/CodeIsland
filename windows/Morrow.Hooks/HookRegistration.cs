namespace Morrow.Hooks;

public sealed record HookRegistration(
    string Id,
    string Command,
    IReadOnlyList<string> Events,
    int ProtocolVersion,
    string InstallerVersion)
{
    public const int CurrentProtocolVersion = 1;
    // 0.2.2: the Claude Code hook no longer passes --source (see KnownTools); bumping marks
    // existing installs outdated so App.RepairOutdatedHooks rewrites them on next launch.
    public const string CurrentInstallerVersion = "0.2.2";

    public static HookRegistration Create(HookTool tool, string bridgePath) => new(
        tool.HookMarker,
        $"\"{Path.GetFullPath(bridgePath)}\" send --stdin --registration {tool.HookMarker}",
        tool.Events,
        CurrentProtocolVersion,
        CurrentInstallerVersion);
}
