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

$server = "" # base URL for Zerto server
$endpoint = $server + ":9669/v1"
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

$body = $null

$vpgList = Invoke-RestMethod -Uri "$endpoint/vpgs" -Headers $zertoSessionHeader -ContentType "application/json" | Sort-Object VpgName

$vpgSorted = $vpgList | Sort-Object -Property VpgName

$body += @"
  <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en" style="min-height:100%; background:#f2f2f2">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <meta name="viewport" content="width=device-width"> 
      </head>
      <body style="-moz-box-sizing:border-box;-ms-text-size-adjust:100%;-webkit-box-sizing:border-box;-webkit-text-size-adjust:100%;Margin:0;box-sizing:border-box;color:#333;font-family:Helvetica,Arial,sans-serif;font-size:13px;font-weight:400;line-height:1.428;margin:0;min-width:100%;padding:0;text-align:left;width:100%!important">
        <div style='text-align: center'>
          <table cellpadding="0" cellspacing="0" border="0" style="padding:0px;margin:0px;width:100%;background:#f2f2f2">
            <tr>
              <td colspan="3" style="padding:0px;margin:0px;font-size:20px;height:20px;" height="20">&nbsp;</td>
            </tr>
            <tr>
              <td style="padding:0px;margin:0px;">&nbsp;</td>
              <td style="padding:0px;margin:0px;" width="800">
                <br />
                <table width='100%' cellpadding="0" cellspacing="0" border='0' style='margin:0; padding:0; border-collapse: collapse; background:#FFF; font-family:Helvetica,Arial,sans-serif'>
                  <tr style="padding:0px;margin:0px;">
                    <td valign="middle" colspan='3' bgcolor='#002e5d' width='500' style='padding: 10px; margin:0px; color: #FFFFFF; font-size: large; height: 35px; text-align: center; vertical-align: middle;'>
                      Zerto Daily RPO Report
                    </td>
                  </tr>
"@

foreach ($vpg in $vpgSorted) {
      $body += @"
                  <tr style="padding:0px 20px;margin:0px;">
                    <td width="200" style="padding: $(if ($vpgSorted[0] -eq $vpg) {'20px'} else {'5px'} ) 0px $(if ($vpgSorted[-1] -eq $vpg) {'20px'} else {'5px'} ) 20px; margin:0px; font-weight: bold; ">$($vpg.VpgName):</td>
                    <td colspan="2" style="padding: 5px 0px 10px 0px; margin:0px;">$(if ($vpg.ActualRPO -gt 1){"$($vpg.ActualRPO) seconds"} else{"$($vpg.ActualRPO) second"})</td>
                  </tr>
"@
  }
  $body += @"
                </table>
              </td>
              <td style="padding:0px;margin:0px;">&nbsp;</td>
            </tr>
            <tr><td colspan="3" style="padding:0px;margin:0px;font-size:20px;height:20px;" height="20">&nbsp;</td></tr>
          </table>
        </div>
      </body>
    </html>
"@

if ($body) {
  $emailFrom = "" # from email
  $emailTo = "" # to email
  $subject = "[Zerto ZVM] Daily RPO Report"
  $smtpServer = "" # SMTP server

  Send-MailMessage -From $emailFrom -To $emailTo -Subject $subject -Body $body -BodyAsHtml -SmtpServer $smtpServer
}

closexZertoSession
