function IsNotAvailable {
    param (
        $Path
    )
    try{
        [System.IO.File]::OpenWrite($Path).close()
        return $false
    }
    catch {
        return $true
    }
}
try {
    $pc = HOSTNAME.EXE
    $source = ""
    $csv = "$source\BitlockerKeys.csv"
    $bitlockerInfo = Get-BitLockerVolume -MountPoint C
    if ($bitlockerInfo.ProtectionStatus -eq "Off") {
        $pc | Out-File -FilePath "$source\Unprotected.txt" -Append
    }
    else {
        $recoveryKeys = @()
        $bitlockerKeys = (Get-BitLockerVolume -MountPoint C).KeyProtector | Where-Object {$_.RecoveryPassword -ne ""}
        ForEach ($item in $bitlockerKeys) {
            $recoveryKeys += [PSCustomObject]@{
                Computer = $pc
                RecoveryID = $item.KeyProtectorId
                RecoveryPassword = $item.RecoveryPassword
            }
        }
        try {
            $recoveryKeys | Select-Object * | Export-Csv -Path $csv -NoTypeInformation -Append
        }
        catch {
            Write-Host $Error[0].Exception.Message
            if ($Error[0].Exception.Message -like "*being used by another process*") {
                while (IsNotAvailable -Path $csv) {
                    Start-Sleep -Milliseconds 100
                }
                $recoveryKeys | Select-Object * | Export-Csv -Path $csv -NoTypeInformation -Append
            }
        }
    }
}
catch {
    $Error[0].Exception.Message | Out-File -FilePath "$source\Error.txt" -Append
}
