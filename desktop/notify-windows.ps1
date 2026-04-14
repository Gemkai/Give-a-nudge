# Give a Nudge — Windows toast notification (opt-in for desktop app users)
# Option 1 (recommended): Install-Module -Name BurntToast -Scope CurrentUser
# Option 2 (fallback): uses built-in .NET Windows Forms balloon tip
# Enable: set NUDGE_DESKTOP_NOTIFY=true in your shell profile
param([string]$Message = "Give a Nudge")

try {
    if (Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue) {
        Import-Module BurntToast
        New-BurntToastNotification -Text "Give a Nudge", $Message
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.BalloonTipTitle = "Give a Nudge"
        $notify.BalloonTipText = $Message
        $notify.Visible = $true
        $notify.ShowBalloonTip(5000)
        Start-Sleep -Seconds 1
        $notify.Dispose()
    }
} catch {
    exit 0
}
