# bypass self-signed certificate
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

$server = "" # IP address of Zerto server

$endpoint = "https://$server" + ":9669/v1"
$strZVMUser = "" # local vSphere user
$strZVMPwd = "" # local vSphere user password

function getxZertoSession {
  param([String]$userName, [String]$password)
  $xZertoSessionURI = $endpoint +"/session/add"
  $authInfo = ("{0}:{1}" -f $userName, $password)
  $authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
  $authInfo = [System.Convert]::ToBase64String($authInfo)
  $headers = @{Authorization=("Basic {0}" -f $authInfo)}
  $contentType = "application/json"
  $xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $headers -Method POST -ContentType $contentType
  return $xZertoSessionResponse.headers.get_item("x-zerto-session")
}

function closexZertoSession {
  $xZertoSessionURI = $endpoint +"/session"
  $contentType = "application/json"
  $xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $zertoSessionHeader -Method DELETE -ContentType $contentType
}

# extract x-zerto-session from the response, and add it to the actual api:
$xZertoSession = getxZertoSession $strZVMUser $strZVMPwd
$zertoSessionHeader = @{"x-zerto-session"=$xZertoSession}

$vpgList = Invoke-RestMethod -Uri "$endpoint/vpgs" -Headers $zertoSessionHeader -ContentType "application/json" | Sort-Object VpgName

$vpgSorted = $vpgList | Sort-Object -Property VpgName

# generate XML for PRTG sensors
Write-Host @"
<prtg>
"@

foreach ($vpg in $vpgSorted) {
    Write-Host @"
        <result>
            <channel>$($vpg.VpgName)</channel>
            <value>$($vpg.ActualRPO)</value>
            <unit>TimeSeconds</unit>
        </result>
"@
}

Write-Host @"
</prtg>
"@

closexZertoSession
