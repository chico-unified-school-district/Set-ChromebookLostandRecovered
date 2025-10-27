<#
.SYNOPSIS
Update attributes for lost and recovered Chromebook devices.
.NOTES
 Starting tag is CB201800012001
 Tag number should always be 14 characters in length
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $true)]
 [Alias('Server')]
 [string]$SQLServer,
 [Parameter(Mandatory = $true)]
 [Alias('Database')]
 [string]$SQLDatabase,
 [Parameter(Mandatory = $true)]
 [Alias('DBCred', 'Cred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 [Parameter(Mandatory = $False)]
 [string]$StopTime = "5:00pm",
 [Alias('wi')]
 [SWITCH]$WhatIf
)

function Add-GData {
 begin {
  $crosFields = "annotatedUser,annotatedAssetId,orgUnitPath,deviceId,status"
 }
 process {
  Write-Verbose ("& $gam print cros query `"asset_id: $($_.barcode)`" fields $crosFields")
  ($gDev = & $gam print cros query "asset_id: $($_.barcode)" fields $crosFields) *>$null
  $devObj = $gDev | ConvertFrom-Csv
  $msg = $MyInvocation.MyCommand.Name, $_.gmail, $_.barcode
  if (-not$devObj) { return (Write-Verbose ("{0},[{1}],[{2}] No dev found" -f $msg)) }
  $_.devId = $devObj.deviceId
  $_.status = $devObj.status
  $_.devUser = $devObj.annotatedUser
  $_.ou = $devObj.orgUnitPath.Trim() # Trim justin case
  Write-Verbose ( $MyInvocation.MyCommand.Name, $_ | Out-String )
  Write-Debug ('{0},[{1}],[{2}],Proceed?' -f $msg)
  $_
 }
}

function Complete-Processing {
 process {
  # Write-Verbose ( $MyInvocation.MyCommand.Name, $_ | Out-String )
  $msg = $MyInvocation.MyCommand.Name, $_.barcode, $_.gmail
  Write-Verbose ('{0},[{1}],[{2}]' -f $msg)
 }
}

function Format-Obj {
 process {
  [PSCustomObject]@{
   stuId   = $_.id
   gmail   = $_.gmail
   barcode = $_.barcode
   code    = $_.code
   school  = $_.school
   rin     = $_.RIN
   devId   = $null
   devUser = $null
   status  = $null
   targOU  = $null
   action  = $null
   ou      = $null
   dts     = $_.dts
  }
 }
}

function Get-Devices ($params) {
 $query = Get-Content .\sql\query-devices.sql -Raw
 $data = New-SqlOperation @params -Query $query  | ConvertTo-CSV | ConvertFrom-Csv
 Write-Verbose ('{0}, Count: {1}' -f $MyInvocation.MyCommand.Name, @($data).count)
 $data
}

function Set-CodeData {
 begin {
  function Search-Code ($code) {
   # Select GSuite OU and action based on listed device code
   switch ($code) {
    # Create Hash Data
    M { @{ou = '/Chromebooks/Missing'; action = 'disable' } }    # Lost
    S { @{ou = '/Chromebooks/Missing'; action = 'disable' } }    # Stolen
    V { @{ou = '/Chromebooks/Cart'; action = 'reenable' } }      # Recovered/Reactivate
    default { @{ou = '/Chromebooks/Missing'; action = 'disable' } }
   }
  }
 }
 process {
  $codeData = Search-Code $_.code
  $_.targOU = $codeData.ou
  $_.action = $codeData.action
  $_
 }
}

function Update-OU {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barcode, $_.ou, $_.targOU
  if ($_.ou -eq $_.targOU) { return (Write-Verbose ("{0},[{1}],[{2}] = [{3}] OU is correct" -f $msg)), $_ }
  Write-Host ('{0},[{1}],[{2}] -> [{3}] ' -f $msg) -F Blue
  Write-Host "& $gam update cros $($_.devId) ou `"$($_.targOU)`"" -F Blue
  if (-not$WhatIf) { (& $gam update cros $_.devId ou "$($_.targOU)") *>$null }
  $_
 }
}

function Update-Gmail {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barcode
  # Skip if gmail missing from SIS database
  if ($_.gmail -notmatch '@') { return (Write-verbose ('{0},[{1}],Gmail Missing from DB' -f $msg)), $_ }
  # Skip already if matching
  if ($_.gmail -match $_.devUser) { return (Write-verbose ('{0},[{1}],DB matches Gsuite' -f $msg)), $_ }
  Write-Host ("{0},[{1}],[$($_.gmail)]" -f $msg) -F Blue
  Write-Host "& $gam update cros $($_.devId) user $($_.gmail)" -F Blue
  if (-not$WhatIf) { (& $gam update cros $_.devId user $_.gmail) *>$null }
  $_
 }
}

function Set-DeviceStatus {
 process {
  if ( ($_.action -eq 'disable') -and ($_.status -eq "DISABLED") ) { return $_ }
  if ( ($_.action -eq 'reenable') -and ($_.status -eq "ACTIVE") ) { return $_ }
  $msg = $MyInvocation.MyCommand.Name, $_.barcode , "& $gam update cros $($_.devId) action $($_.action)"
  Write-Host ('{0},[{1}],[{2}]' -f $msg) -F Blue
  if (-not$WhatIf) { (& $gam update cros $_.devId action $_.action) *>$null }
  $_
 }
}

function Set-TicketDate ($params) {
 begin {
  $baseSql = Get-Content -Path .\sql\update-dd.sql -Raw
 }
 process {
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $_.barcode) -F Blue
  if ($null -eq $_.stuId) {
   return (Write-Error ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $_.barcode)), $_
  }
  # Fill in 'Last Ticket Date' [DRA].[DD] field to prevent duplicate processing
  $sqlVars = "id=$($_.stuId)", "scl=$($_.school)", "cd=$($_.code)", "rin=$($_.RIN)"
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, ($sqlVars -join ','))
  if (!$WhatIf) {
   try { New-SqlOperation @params -Query $baseSql -Parameters $sqlVars }
   catch { return }
  }
  $_
 }
}

function Skip-Staff {
 process {
  if ($_.ou -like "*Teacher*") { return }
  $_
 }
}

# ======================================== Main =======================================
Import-Module -Name 'dbatools', 'CommonScriptFunctions'
Show-BlockInfo Start

if ($WhatIf) { Show-TestRun }
$gam = '.\bin\gam.exe'

$sqlParams = @{
 Server     = $SQLServer
 Database   = $SQLDatabase
 Credential = $SQLCredential
}

'Runs every 60 seconds'
do {
 Get-Devices $sqlParams |
  Format-Obj |
   Set-CodeData |
    Add-GData |
     Skip-Staff |
      Update-OU |
       Update-Gmail |
        Set-DeviceStatus |
         Set-TicketDate $sqlParams |
          Complete-Processing
 if (!$WhatIf) { Start-Sleep -Seconds 60 }
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )

if ($WhatIf) { Show-TestRun }
Show-BlockInfo End