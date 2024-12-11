$authToken = (Import-Clixml -Path "token.xml").GetNetworkCredential().Token # generate auth token from Meraki and save via Export-Clixml
$orgId = "" # get from dashboard

$headers = @{
    'Content-Type'  = 'application/json'
    'Accept'        = 'application/json'
    'Authorization' = "Bearer $authToken"
}

$devicesUrl = "https://api.meraki.com/api/v1/organizations/$orgId/devices/availabilities"
$devices = Invoke-RestMethod -Uri $devicesUrl -Headers $headers

# generate XML for PRTG sensor
Write-Host @"
<prtg>
"@

foreach ($device in $devices) {
    $name = if (!$device.name) {
        $device.mac
    }
    else {
        $device.name
    }
    $status = switch ($device.status) {
        "online" { 1 }
        "dormant" { 2 }
        "offline" { 3 }
        Default { 1 }
    }
    Write-Host @"
    <result>
        <channel>$name</channel>
        <value>$status</value>
        <limitmaxerror>2</limitmaxerror>
        <limiterrormsg>$name is Offline</limiterrormsg>
    </result>
"@
}

Write-Host @"
</prtg>
"@
