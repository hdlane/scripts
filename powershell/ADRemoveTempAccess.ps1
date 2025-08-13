$TemporaryOU = "" # distinguished name of temporary OU
$TargetOU = "OU=Target OU,DC=example,DC=com" # distinguished name of target OU to put the computer back into
Get-ADComputer -Filter * -SearchBase $TemporaryOU | Move-ADObject -TargetPath $TargetOU
