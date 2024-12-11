Add-Type @"
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
  $xZertoSessionURI = $endpoint + "/session/add"
  $authInfo = ("{0}:{1}" -f $userName, $password)
  $authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
  $authInfo = [System.Convert]::ToBase64String($authInfo)
  $headers = @{Authorization = ("Basic {0}" -f $authInfo) }
  $contentType = "application/json"
  $xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $headers -Method POST -ContentType $contentType
  return $xZertoSessionResponse.headers.get_item("x-zerto-session")
}

function closexZertoSession {
  $xZertoSessionURI = $endpoint + "/session"
  $contentType = "application/json"
  $xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $zertoSessionHeader -Method DELETE -ContentType $contentType
}

# extract x-zerto-session from the response, and add it to the actual api:
$xZertoSession = getxZertoSession $strZVMUser $strZVMPwd
$zertoSessionHeader = @{"x-zerto-session" = $xZertoSession }

$body = $null

$lastHour = (Get-Date).AddHours(-1)
$alerts = Invoke-RestMethod -Method Get -Uri "$endpoint/alerts" -Headers $zertoSessionHeader -ContentType "application/json"
$alertsLastHour = $alerts | Where-Object { [DateTime]$_.TurnedOn -le $lastHour }

if ($alertsLastHour) {
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
                <table width='100%' cellpadding="0" cellspacing="0" border='0' style='margin:0; padding:0; border-collapse: collapse; background:#FFF; font-size: 13px; font-family:Helvetica,Arial,sans-serif'>
                  <tr style="padding:0px;margin:0px;">
                    <td valign="middle" colspan='3' bgcolor='#ba0c2f' width='500' style='padding: 10px; margin:0px; color: #FFFFFF; font-size: large; height: 35px; text-align: center; vertical-align: middle;'>
                      $(
                        if ($alertsLastHour.Count -gt 1) {
                              "Zerto Alerts ($($alertsLastHour.Count) Total)"
                          } else {
                              "Zerto Alert"
                          }
                      )
                    </td>
                  </tr>
"@
  foreach ($alert in $alertsLastHour) {
    $time = [datetime]$alert.TurnedOn
    $body += @"
                  <tr style="padding:0px;margin:0px;">
                    <td colspan="3" style="padding: 20px; margin: 0px; color: #ba0c2f; text-align:left; font-weight: bold;">Alert Description</td>
                  </tr>
                  <tr style="padding:0px;margin:0px;">
                    <td colspan="3" style="padding: 0px 20px; margin: 0px;">The following Zerto alert has been triggered: $($alert.Description)</td>
                  </tr>
                  <tr style="padding:0px;margin:0px;">
                    <td colspan="3" style="padding: 20px; margin:0px;">
                      <hr style="border-width: 0; background: #d1ccbd; color: #d1ccbd; height:0.5px;">
                    </td>
                  </tr>
                  <tr style="padding:0px;margin:0px;">
                    <td colspan="3" style="padding: 0px 20px 20px 20px; margin:0px; color: #ba0c2f; text-align:left; font-weight: bold;">Alert Details</td>
                  </tr>
                  <tr style="padding:2px 20px;margin:0px;">
                    <td width="200" style="padding: 0px 0px 0px 20px; margin:0px; font-weight: bold; ">Severity:</td>
                    <td colspan="2" style="padding: 0px; margin:0px;">$($alert.Level): $($alert.HelpIdentifier)</td>
                  </tr>
                  <tr style="padding:2px 20px;margin:0px;">
                    <td width="200" style="padding: 0px 0px 0px 20px; margin:0px; font-weight: bold">Occurred At:</td>
                    <td colspan="2" style="padding: 0px; margin:0px;">$($time.ToString("MM/dd/yy hh:mm:ss tt"))</td>
                  </tr>
                  <tr style="padding:2px 20px;margin:0px;">
                    <td colspan="3" style="padding: 20px; margin:0px; font-size:12px; color: #777777; text-align:left;">
                      Additional details for the alert including possible causes and steps for resolution can be found at: <a href="https://help.saas.zerto.com/index.html#context/ErrorsGuide/$($alert.HelpIdentifier)">https://help.saas.zerto.com/index.html#context/ErrorsGuide/$($alert.HelpIdentifier)</a>
                    </td>
                  </tr>
                  <tr style="padding:20px;margin:0px;">
                   <td colspan="3" style="padding:0px;margin:0px;">&nbsp;</td>
                  </tr>
                  $(
                    if ($alertsLastHour.Count -gt 1) {
                      if ($alertsLastHour[-1] -eq $alert) {
                          ""
                      } else {
                          "<tr style='padding:0px;margin:0px;'><td colspan='3' style='padding: 0px; margin:0px;'><hr style='border-width: 0; background: #d1ccbd; color: #d1ccbd; height:10px'></td></tr>"
                      }
                  }
                  )
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
}

if ($body) {
  $emailFrom = "" # from address
  $emailTo = "" # to address
  $subject = "[Zerto ZVM] Alert Triggered"
  $smtpServer = "" # SMTP server

  Send-MailMessage -From $emailFrom -To $emailTo -Subject $subject -Body $body -BodyAsHtml -SmtpServer $smtpServer
}

closexZertoSession
