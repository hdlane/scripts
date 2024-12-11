<# 
ABOUT
This script queries Cisco Unity using a created API user, and emails voicemail messages 
that arrived within 10 minutes to users.

SUMMARY
    Connect to CUC server
    Get users (all or those listed in TXT file)
    Check that user is in Unity
    Get voicemail inboxes for users
    Check messages that are unread and less than 10 minutes old
    Get message .wav file
    Attach and email to user
    Log operations
    Run as scheduled task on server every 10 minutes
#>

# Bypasses SSL cert checking due to self-signed, expired cert
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$Destination = "" # root directory for script
$LogFile = "$Destination\Logs\Log-$(Get-Date -Format 'yyyy-MM-dd-hhmmss').txt"
$MessagesPath = "$Destination\Messages\"
$UserListPath = "$Destination\UserList.txt" # list of users to check, but if not there all users will be queried

Function LogMessage {
    param (
        [Parameter(Mandatory)]
        [String]
        $Message
    )
    Add-Content -Path $LogFile $Message
}

function Remove-Logs {
    $timeFrame = (Get-Date).AddHours(-24)
    $logFiles = Get-ChildItem -Path $LogFolderPath -Filter *.txt | Where-Object { $_.LastWriteTime -lt $timeFrame }
    if (! ($logFiles)) {
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: No log files to delete"
    }
    else {
        foreach ($file in $logFiles) {
            try {
                Remove-Item $file.FullName -Force
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Deleted log file '$($file.Name)'"
            }
            catch {
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR: Got error trying to delete log file '$($file.Name)': $_"
            }
            
        }
    }
}

#Begin script execution timer
$startTime = (Get-Date)
New-Item -Path $LogFile -ItemType File -Value "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Cleaning up log files older than 24 hours...`n" -Force

Remove-Logs

function Connect-CUCServer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Endpoint,
        [Parameter()]
        [string]
        $Outfile,
        [Parameter()]
        [string]
        $Alias
    )

    $server = "" # server URL
    # save credentials to encrypted XML via Export-Clixml:
    # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml?view=powershell-7.4#example-3-encrypt-an-exported-credential-object-on-windows
    $username = (Import-Clixml -Path "$Destination\CUC.xml").GetNetworkCredential().Username
    $password = (Import-Clixml -Path "$Destination\CUC.xml").GetNetworkCredential().Password
    $encodedAuthorization = [System.Text.Encoding]::UTF8.GetBytes($username + ":" + $password)
    $encodedPassword = [System.Convert]::ToBase64String($encodedAuthorization)

    $headers = @{
        Authorization   = "BASIC $($encodedPassword)"
        Accept          = 'application/json'
        "Cache-Control" = "no-cache"
        "User-Agent"    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36 Edge/16.16299"
    }
    try {
        if ($Outfile) {
            try {
                Invoke-RestMethod -Uri $($server + $Endpoint) -Method Get -Headers $headers -OutFile $Outfile
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: [$Alias] SUCCESS! Saved message as '$outfile'"
            }
            catch {
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") WARN: [$Alias] $_"
            }
        }
        else {
            Invoke-RestMethod -Uri $($server + $Endpoint) -Method Get -Headers $headers
        }
    }
    catch {
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") WARN: Error connecting to CUC: '$_'"
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") WARN: Attempted the following request: '$($server + $Endpoint)'"
    }
}

function Get-CUCAllUsers {
    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Searching Unity for all users..."
    Connect-CUCServer -Endpoint "/vmrest/users"
}

function Get-CUCUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Alias
    )
    Connect-CUCServer -Endpoint "/vmrest/users/?query=(alias%20startswith%20$Alias)"
}

function Send-CUCRecentMessages {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Path,
        [Parameter(Mandatory)]
        [string]
        $Recipient,
        [Parameter()]
        [string]
        $Subject,
        [Parameter(Mandatory)]
        [string]
        $Attachments,
        [Parameter(Mandatory)]
        [string]
        $Alias
    )
    
    $emailParams = @{
        From        = "" # from email address
        To          = $Recipient
        Subject     = $Subject
        SMTPServer  = "" # SMTP server
        Attachments = $Attachments
    }
    $emailParams.Body = @"
<!DOCTYPE html>
<html>
<head>
</head>
<body>
    <p><span style="color:#CE2029; font-weight:bold">NOTE: Deleting this email will not delete it from your voicemail box</span></p>
</body>
</html>
"@
    if (! ($Recipient)) {
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR: [$Alias] ERROR! No email address provided for user! Check for an email in Unified Messaging Accounts"
    }
    else {
        try {
            LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: [$Alias] Sending email to $Recipient..."
            Send-MailMessage @emailParams -BodyAsHtml -ErrorAction Stop
            LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: [$Alias] SUCCESS! Sent email to $Recipient with attachment $Attachments"
        }
        catch {
            LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR: [$Alias] ERROR! Got error trying to send email: $_"
        }
    }
    
}

function Get-CUCRecentMessages {
    # URL scheme: https://server/vmrest/messages/$MsgId/attachments/0/?userobjectid=$ObjectId&filename=voicemessage.wav
    # Example: https://server/vmrest/messages/0:77113891-660b-4541-a934-6f0e69ef2541/attachments/0/?userobjectid=86346d53-6ac9-42c9-9307-be2914bdbc9e&filename=voicemessage.wav
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $SavePath,
        [Parameter()]
        [string]
        $UserList
    )

    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Beginning Cisco Unity Voicemail Check..."

    if ($UserList) {
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: User list specified at $($UserList)"
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Checking path..."
        if (Test-Path $UserList) {
            LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: User List found!"
            $users = @()
            $list = Get-Content $UserList | Sort-Object
            if ($list.Count -ne 1) {
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Searching Unity for $($list.Count) users"
            }
            else {
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Searching Unity for $($list.Count) user"
            }
            foreach ($user in $list) {
                $checkUser = (Get-CUCUser -Alias $user).User
                if ($checkUser) {
                    $users += $checkUser
                }
                else {
                    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") WARN: [$user] User with alias '$user' not found in Unity. Skipping message query for this user..."
                }
            }
        }
        else {
            LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR: User List not found! Stopping the task and sending alert email."
            try {
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Sending alert email..."
                Send-MailMessage -To "me@example.com" -From "italerts@example.com" -Subject "CISCO UNITY VOICEMAIL TASK FAILED!" -Body "ERROR: During the task the User List was specified but not found." -SmtpServer "email.example.com" -ErrorAction Stop
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Email sent. Stopping task..."
            }
            catch {
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR: Error occurred while trying to send email: $_"
                LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Stopping task..."
            }
            LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Exiting with error code 1"
            exit 1
        }
    }
    else {
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: No User list specified. Searching Unity for all users"
        $users = (Get-CUCAllUsers).User | Sort-Object -Property Alias
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Found $($users.Count)"
    }
    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Beginning query for unread voicemail messages within the last 10 minutes..."
    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Note: Only users that receieved messages will show on this log"
    $recentMessages = @()
    foreach ($user in $users) {
        $userMessages = @()
        
        $userObjectId = $user.ObjectId
        $userSMTP = (Connect-CUCServer -Endpoint "/vmrest/users/$userObjectId/externalserviceaccounts").ExternalServiceAccount.EmailAddress
        $messages = (Connect-CUCServer -Endpoint "/vmrest/mailbox/folders/inbox/messages?userobjectid=$($userObjectId)&read=false").Message | Where-Object { ([TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date -Date "1970-01-01 00:00:00").AddMilliseconds($_.ArrivalTime), "UTC", "Central Standard Time")) -gt ((Get-Date).AddMinutes(-10)) }

        $recentMessages += [PSCustomObject]@{
            User    = $userSMTP
            UserId  = $userObjectId
            Message = $messages
        }

        $userMessages = [PSCustomObject]@{
            User    = $userSMTP
            UserId  = $userObjectId
            Message = $messages
        }
        if ($userMessages.Message) {
            foreach ($message in $userMessages.Message) {
                $outfile = $SavePath
                $outfile += "$($user.Alias) $(([TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date -Date "1970-01-01 00:00:00").AddMilliseconds($message.ArrivalTime), "UTC", "Central Standard Time")).ToString('MM-dd-yy hh-mm-sstt')).wav"
                try {
                    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: [$($user.Alias)] Message Found: Trying https://server/vmrest/messages/$($message.MsgId)/attachments/0/?userobjectid=$($userObjectId)&filename=voicemessage.wav"
                    Connect-CUCServer -Endpoint "/vmrest/messages/$($message.MsgId)/attachments/0/?userobjectid=$($userObjectId)&filename=voicemessage.wav" -OutFile $outfile -Alias $user.Alias
                    if (Test-Path $outfile) {
                        Send-CUCRecentMessages -Path $outfile -Recipient $userSMTP -Subject $message.Subject -Attachments $outfile -Alias $user.Alias
                        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: [$($user.Alias)] Removing file: $outfile..."
                        Remove-Item -Path $outfile -ErrorAction Stop
                    }
                    else {
                        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") WARN: [$($user.Alias)] Unable to find $outfile. It may have recently been read or deleted. Not sending email."
                    }
                }
                catch {
                    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt")  ERR: [$($user.Alias)] ERROR! Attempted to save as '$outfile' but got an error message: $_. Not sending email."
                    Send-MailMessage -To "me@example.com" -From "italerts@example.com" -Subject "CISCO UNITY VOICEMAIL TASK ERROR!" -Body "ERROR: Tried to send email to $($user.Alias) and got this error: $_" -SmtpServer "email.example.com" -ErrorAction Stop
                }
            }
        }     
    }
    if (! ($recentMessages.Message)) {
        LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: No new messages found within the last 10 minutes"
    }
    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Voicemail Check Complete!"
}

Get-CUCRecentMessages -SavePath $MessagesPath -UserList $UserListPath

#End script execution timer
$endTime = (Get-Date)
$diffTime = $endTime - $startTime
if ($diffTime.TotalMinutes -lt 1) {
    $executionTime = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Time to execute script: $executionTime seconds"
}
else {
    $executionTime = [math]::Round(($endTime - $startTime).TotalMinutes, 2)
    LogMessage "$(Get-Date -Format "h:mm:ss.ff tt") INFO: Time to execute script: $executionTime minutes"
}
