<# 
    ABOUT
    Alerts users via email about their Windows password expiring

    SUMMARY
    Uses Active Directory module to pull all user accounts and filters out
    accounts that are disabled, password never expires, and don't have an email.
#>

$expirationThreshold = (Get-Date).AddDays(7)
$users = Get-ADUser -Filter * -Properties msDS-UserPasswordExpiryTimeComputed, EmailAddress, PasswordNeverExpires | Where-Object { ($_.PasswordNeverExpires -eq $false) -and ($_."msDS-UserPasswordExpiryTimeComputed" -ne 0) -and ($_.Enabled -eq $true) -and ($_.EmailAddress -ne $null) }

function Send-Email {
    param (
        [string]$name,
        [string]$recipient,
        [datetime]$expirationDate
    )

    $head = @"
    <head><style>body {font-family: arial;text-align: center;}ul {list-style: none;}table {table-layout: fixed;}table.head-section {width: 100%;font-size: 30pt;background-color: #002e5d;padding: 20px 0;color: #fff;}table.desc-section {width: 75%;}table.desc-section tr td.cell-description {padding: 15px 0;}table.misc-section tr {font-size: 10pt;color: #314444;}table.misc-section tr td {padding: 0 10px;}table.misc-section tr .cell-label {width: 50%;text-align: right;}table.misc-section tr .cell-value {width: 50%;font-weight: bold;text-align: left;}small {font-size: 8pt;color: #647777;}a.button {font: bold 15px Arial;text-decoration: none;color: #314444;padding: 10px 30px 10px 30px;border-top: 1px solid #cccccc;border-right: 1px solid #333333;border-bottom: 1px solid #333333;border-left: 1px solid #cccccc;}</style></head>
"@
    $body = @"
    <body>
        <table align='center' class='head-section'>
            <tr>
                <td class='cell-h1'>Windows Password Expiration Notice</td>
            </tr>
        </table>
        <table align='center' class='desc-section'>
            <tr>
                <td class='cell-description'>$($name), your Windows password is set to expire soon. Please change it before that time to prevent issues while working. You can do that by pressing Ctrl + Alt + Delete, and selecting 'Change a password.'</td>
            </tr>
        </table>
        <table align='center' class='misc-section'>
            <tr><td class='cell-label'>Expiration Date:</td><td class='cell-value'>$($expirationDate.ToString('g'))</td></tr>
        </table>
        <br>
        <footer>
            <small>If you have questions regarding the legitimacy of this email, please contact helpdesk@armstrongbank.com for assistance.</small>
        </footer>
    </body>
"@
    $emailBody = $head + $body
    
    $emailData = @{
        Subject    = "Windows Password Expiration Notice"
        From       = "" # from email address
        To         = $recipient
        Body       = $emailBody
        BodyAsHtml = $true
        SmtpServer = "" # SMTP server
    }

    Send-MailMessage @emailData
}

foreach ($user in $users) {
    if ($user."msDS-UserPasswordExpiryTimeComputed" -eq 0) {
        Continue
    }
    else {
        $expirationDate = [datetime]::FromFileTime($user."msDS-UserPasswordExpiryTimeComputed")
        if ($expirationDate -le $expirationThreshold) {
            Send-Email -name $user.GivenName -recipient $user.EmailAddress -expirationDate $expirationDate
        }
    }
}
