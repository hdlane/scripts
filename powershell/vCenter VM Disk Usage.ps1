# used by SSRS to generate disk usage reports
#
# create a database table with fields:
# id (don't touch - auto-increments)
# recorded_at (date)
# computer_name (nvarchar(128))
# host_name (nvarchar(128))
# drive (nchar(1))
# disk_capacity (numeric(18, 0))
# disk_free (numeric(18, 0))

$SqlServer = "" # SQL server instance
$SqlTable = "" # format = [DATABASE].[dbo].[table_name]
$ColumnList = "[recorded_at], [computer_name], [drive], [disk_capacity], [disk_free]"

$vCenterServer = "" # vCenter IP address

$VMs = @(
    $connect = Connect-VIServer -Server $server -User "" -Password "" # enter vSphere user
    Get-VM
)

$ValuesList = ForEach ($VM in $VMs) {
    ForEach ($Disk in $VM.ExtensionData.Guest.Disk | Where-Object {$_.DiskPath -like "*:\"}) {
        "('$(get-date -format "MM/dd/yyyy")', '$($VM.ExtensionData.Guest.HostName)', '$($Disk.DiskPath.Replace(":\", ''))', $([math]::Round($Disk.Capacity/1GB,2)), $([math]::Round($Disk.FreeSpace/1GB,2))),"
    }
}

$InsertQuery = "INSERT INTO [ITDB].[dbo].[computer_disk] ($ColumnList) VALUES $ValuesList".TrimEnd(",")
Invoke-Sqlcmd -Query $InsertQuery -ServerInstance $SqlServer

Disconnect-VIServer -Server $server -Confirm:$false
