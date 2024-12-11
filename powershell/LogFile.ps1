#Log file templates:
#LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO:"
#LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") WARN:"
#LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR:"

$LogFile = "\\path\Logs\Log-$(Get-Date -Format 'yyyy-MM-dd-hhmmss').txt"

Function LogMessage {
    param (
        [Parameter(Mandatory)]
        [String]
        $Message
    )
    Add-Content -Path $LogFile $Message
}

New-Item -Path $LogFile -ItemType File -Value "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Beginning Logging...`n" -Force #New line character `n only needed once in the script