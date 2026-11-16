namespace Morrow.Core;

public enum SessionState
{
    Idle,
    Running,
    WaitingForPermission,
    WaitingForAnswer,
    Completed,
    Failed,
    Cancelled
}
