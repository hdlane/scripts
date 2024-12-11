# bypass selfsigned certificate
add-type @"
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

# enter Veeam authentication information
$endpoint = ""
$username = ""
$password = ""

function getVeeamAccessToken {
    param([string]$username, [string]$password)
    $headers = @{
        'x-api-version'='1.0-rev1'
        'accept'='application/json'
        'Content-Type'='application/x-www-form-urlencoded'
    }
    $body = "grant_type=password&username=$username&password=$password"
    $response = Invoke-RestMethod -uri "$endpoint/oauth2/token" -Method Post -headers $headers -Body $body
    return $response.access_token
}

$veeamAccessToken = getVeeamAccessToken $username $password
$veeamHeader = @{
    "x-api-version"="1.0-rev1"
    "accept"="application/json"
    "Authorization"="Bearer $veeamAccessToken"
}

# gather Veeam jobs and enumerate jobs based on status
$veeamJobs = Invoke-RestMethod -Uri "$endpoint/v1/jobs/states" -Method Get -Headers $veeamHeader | Select-Object -ExpandProperty data | Sort-Object -Property name

$jobsSuccess = $veeamJobs | Where-Object {$_.lastResult -eq "Success"}
$jobsWarning = $veeamJobs | Where-Object {$_.lastResult -eq "Warning"}
$jobsFailed = $veeamJobs | Where-Object {$_.lastResult -eq "Failed"}
$jobsRunning = $veeamJobs | Where-Object {$_.status -eq "running"}
$jobsFinished = $veeamJobs | Where-Object {$_.status -eq "inactive"}
$jobsScheduled = $veeamJobs | Where-Object {$_.status -eq "inactive" -and $_.nextRun -like "*"}

# generate XML for PRTG sensors
Write-Host @"
<prtg>
    <result>
        <channel>Job Runs Successful</channel>
        <value>$($jobsSuccess.Count)</value>
    </result>
    <result>
        <channel>Job Runs Warning</channel>
        <value>$($jobsWarning.Count)</value>
        <limitmaxwarning>0</limitmaxwarning>
        <limitmode>1</limitmode>
    </result>
    <result>
        <channel>Job Runs Failed</channel>
        <value>$($jobsFailed.Count)</value>
        <limitmaxwarning>0</limitmaxwarning>
        <limitmode>1</limitmode>
    </result>
    <result>
        <channel>Job Runs Running</channel>
        <value>$($jobsRunning.Count)</value>
    </result>
    <result>
        <channel>Job Runs Finished</channel>
        <value>$($jobsFinished.Count)</value>
    </result>
    <result>
        <channel>Jobs Scheduled</channel>
        <value>$($jobsScheduled.Count)</value>
    </result>
"@

foreach ($job in $veeamJobs) {
    $resultCode = switch ($job.lastResult) {
        "Success" {1}
        "Warning" {2}
        "Failed" {3}
    }
    Write-Host @"
    <result>
        <channel>$($job.name)</channel>
        <value>$resultCode</value>
        <limitmaxwarning>1</limitmaxwarning>
        <limitmaxerror>2</limitmaxerror>
        <limitmode>1</limitmode>
    </result>
"@
}

Write-Host @"
</prtg>
"@
