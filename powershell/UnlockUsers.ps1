function Unlock-Users
{
    [CmdletBinding()]

    $usersList = @()

    $users = Get-ADUser -Filter * -Properties LockedOut, Office | 
        Where-Object { $_.LockedOut -eq $True } | 
        Sort-Object -Property Name | 
        Select-Object -Property Name, SamAccountName, Office, LockedOut

    foreach ($user in $users)
    {
        $usersList += @{
            Name           = $user.Name
            Office         = $user.Office
            Number         = ([array]::IndexOf($users.Name, $user.Name)) + 1
            SamAccountName = $user.SamAccountName
        }
    }
    
    if (! ($users))
    {
        Write-Host "No users are locked out at this time"
    } else
    {
        Write-Host "The following user(s) are locked out"
        $usersList | ForEach-Object { [PSCustomObject] $_ } | Format-Table Number, Name, Office
        do
        {
            $enteredUser = Read-Host "Enter the Number of the user to unlock, or press Ctrl+C to exit"
            $selectedUser = $enteredUser -as [int]

            if (! ($usersList.Number -contains $selectedUser))
            {
                Write-Host "No user in this list matches that number"
            }
        } until ($usersList.Number -contains $selectedUser)
        
        try
        {
            $unlockName = $usersList[[array]::IndexOf($usersList.Number, $selectedUser)].Name
            $unlockSamAccountName = $usersList[[array]::IndexOf($usersList.Number, $selectedUser)].SamAccountName
            Write-Host "Unlocking $unlockName..."
            Unlock-ADAccount -Identity $unlockSamAccountName
            Write-Host "$unlockName has been unlocked!"
        } catch
        {
            Write-Warning "Error occurred while unlocking account: $_"
        }
    }
}
