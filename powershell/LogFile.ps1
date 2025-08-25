#LogMessage usage:
#LogMessage -Message "Beginning Logging..." -Severity INFO

$logsDirectory = "\\path\Logs"
$logFile = "$(Get-Date -Format 'yyyy-MM-dd-hhmmss').log"

Function LogMessage {
    param (
        [Parameter(Mandatory)]
        [String]
        $Message,
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        $Severity
    )
    Add-Content -Path "$($logsDirectory)\$($logFile)" "$(Get-Date -Format "hh:mm:ss.ff tt") $($Severity): $($Message)"
}

New-Item -Path "$($logsDirectory)\$($logFile)" -ItemType File -Force
