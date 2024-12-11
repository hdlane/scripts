$TemporaryOU = "" # distinguished name of temporary OU
$TargetOU = "OU=Windows 10 Computers,DC=armstrong,DC=local" # distinguished name of target OU to put the computer back into
Get-ADComputer -Filter * -SearchBase $TemporaryOU | Move-ADObject -TargetPath $TargetOU
