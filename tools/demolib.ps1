# demolib.ps1 -- read-only Web API access to the usdemo01 environment.
# Uses "pac org who --environment <url>" to mint a token WITHOUT changing the active auth
# profile, so work against cus-con-sandbox is unaffected.
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\phase1\scripts\dvlib.ps1')
$script:DemoUrl = 'https://operations-usdemo01.crm.dynamics.com'
function Invoke-Demo([string]$Path){
  $t=(Get-DvCacheEntries | Where-Object { $_.Target -like '*usdemo01*' } | Sort-Object ExpiresUtc -Descending | Select-Object -First 1)
  if(-not $t -or ($t.ExpiresUtc - (Get-Date).ToUniversalTime()).TotalSeconds -lt 120){
    & pac org who --environment "$script:DemoUrl/" *> $null
    $t=(Get-DvCacheEntries | Where-Object { $_.Target -like '*usdemo01*' } | Sort-Object ExpiresUtc -Descending | Select-Object -First 1) }
  $h=@{Authorization="Bearer $($t.Secret)";Accept='application/json';'OData-MaxVersion'='4.0';'OData-Version'='4.0'}
  try { (Invoke-WebRequest -Uri "$script:DemoUrl/api/data/v9.2/$Path" -Headers $h -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json }
  catch { $d=''; try{$s=$_.Exception.Response.GetResponseStream();$s.Position=0;$d=(New-Object System.IO.StreamReader($s)).ReadToEnd()}catch{}
          [pscustomobject]@{Ok=$false;Status=[int]$_.Exception.Response.StatusCode;Detail=$d} } }
