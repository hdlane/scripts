function Reset-Password {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $user
    )
    $plainPw = "Temp-Password.$(Get-Date -Format "yy")"
    $encodedPw = (ConvertTo-SecureString -AsPlainText $plainPw -Force)
    $confirmation = Read-Host "You are about to reset password for $user to '$plainPw'. Continue? [y/n]"
    while ($confirmation -ne "y") {
        if ($confirmation -eq "n") { 
            Write-Host "Cancelling..."
            break 
        }
        $confirmation = Read-Host "You are about to reset password for $user to '$plainPw'. Continue? [y/n]"
    }
    if ($confirmation -eq "y") {
        Set-ADAccountPassword -Identity $user -NewPassword $encodedPw -Reset -PassThru | Unlock-ADAccount
        Set-ADUser $user -ChangePasswordAtLogon $True
        Write-Host "Temp Password: $plainPw"
    }
}
