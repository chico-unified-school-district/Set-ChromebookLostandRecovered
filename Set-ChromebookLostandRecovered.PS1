#Requires -Version 5.0
<#
.SYNOPSIS
Update attributes for lost and recovered Chromebook devices.
.DESCRIPTION
.EXAMPLE
.INPUTS
.OUTPUTS
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
 [Alias('DBCred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 <# Specify a custom time for the process to end by.
 Defaults to 5:00pm. Loop interval is set to 15 minutes #>
 [Parameter(Mandatory = $False)]
 [string]$StopTime = "5:00pm",
 [SWITCH]$WhatIf
)

# Variable
$ENV:GAM_DEVICE_MAX_RESULTS = 100
$gam = '.\lib\gam-64\gam.exe'

# Imported Functions
. '.\lib\Add-Log.ps1'
. '.\lib\Invoke-SQLCommand.ps1' # Useful function for querying SQL and returning results

# Functions
function setCDData ($code) {
 # Select GSuite OU and action based on listed device code
 switch ($code) {
  # Create Hash Data
  M { @{ou = '/Chromebooks/Missing'; action = 'disable' } 
  } # Lost
  S { @{ou = '/Chromebooks/Missing'; action = 'disable' } 
  } # Stolen
  V { @{ou = '/Chromebooks/Cart'; action = 'reenable' }
  } # Recovered/Reactivate
  R { @{ou = '/Chromebooks/Cart'; action = 'reenable' }
  } # Recovered/Reactivate
  default { @{ou = '/Chromebooks/1:1'; action = 'reenable' }
  }
 }
}

# Processing
"Begin Processing. Running Until $(Get-Date $StopTime)."
$query = Get-Content .\sql\query-devices.sql -Raw
do {
 # Begin Do Loop
 $allCros = $null
 # $allCros = Import-Csv .\all-cros.csv
 $results = Invoke-SQLCommand -Server $SQLServer -Database $SQLDatabase -Credential $SQLCredential -Query $query
 $crosFields = "annotatedUser,annotatedAssetId,orgUnitPath,deviceId,status"
 $deviceCountThreshold = 100 # 67 is the optimal number as determined by benchmarking.
 if ($results.count -gt $deviceCountThreshold) {
  # Compares result count to threshold value
  Write-Verbose "Aeries results ($($results.count)) are over threshold ($deviceCountThreshold)."
  Write-Verbose "Querying all Devices in GSuite"
  ($allCrosRaw = .$gam print cros fields $crosFields) *>$null
  $allCros = $allCrosRaw | ConvertFrom-Csv
 }
 foreach ($dev in $results) {
  $barcode = $dev.barcode
  $email = $dev.StuEmail
  Write-Debug "Process $barcode ?"
  # Search allCROS for matching barcode(asset_id)
  if ($allCros) { $gamDevice = $allCros.where( { $_.annotatedAssetId -eq $barcode }) }
  else { 
   ($gamDeviceRaw = .$gam print cros query "asset_id: $barcode" fields $crosFields) *>$null
   $gamDevice = $gamDeviceRaw | ConvertFrom-Csv 
  }
  if ($gamDevice) {
   # Begin Device Check
   $id = $gamDevice.deviceId
   # Begin Set orgUnitPath and annotatedUser fields in GSuite ====================================
   $cdData = setCDData $dev.code # Select GSuite OU based on listed device code
   $targOU = $cdData.ou
   $cdAction = $cdData.action
   $ouGsuite = ($gamDevice.orgUnitPath | Out-String).Trim() # Fix orgUnitPath string output from gam.exe
   # Skip if already assigned to a teacher/staff
   if ($ouGsuite -like "*Teacher*") {
    Write-Verbose ('{0} already assigned to staff. Skipping.' -f $barcode)
    continue 
   }
   if ($targOU -ne $ouGsuite) {
    # Check for non-matching orUnitPaths
    Write-Verbose "OrgUnitPAth = '$ouGsuite' - Should = '$targOU'"
    if ($email -like "*@*") {
     # Check for non-empty email address
     Add-Log update "$barcode,$email,$targOU" -WhatIf:$WhatIf
     if (!$WhatIf) { (.$gam update cros $id ou $targOU user $email) *>$null }
    }
    else {
     Add-Log update "$barcode,$targOU" -WhatIf:$WhatIf
     if (!$WhatIf) { (.$gam update cros $id ou $targOU) *>$null }
    }
    # End Set orgUnitPath and annotatedUser fields in GSuite ========================================
    # Begin Set device status (action disable/reenable) =======================================
    # Check if GSuite status for device is already correct
    if ( ($cdAction -eq 'disable') -and ($gamDevice.status -eq "DISABLED") ) { continue }
    if ( ($cdAction -eq 'reenable') -and ($gamDevice.status -eq "ACTIVE") ) { continue }
    Add-Log update "$barcode,$cdAction" -WhatIf:$WhatIf
    if (!$WhatIf) { (.$gam update cros $id action $cdAction *>$null) }
    # End Set device status (action disable/reenable) =========================================
   }
   else { Write-Verbose "OrgUnitPath '$targOU' correct for $barcode" }
  }
  else {
   Add-Log warning "$barcode,GSuite asset_id/deviceId not found." -WhatIf:$WhatIf
  }  # End Device Check
 }
 if (!$WhatIf) {
  # $waitTime = 15*60 # Seconds
  $waitTime = 5
  Write-Verbose "Next run at $((Get-Date).AddSeconds($waitTime))."
  Start-Sleep -Seconds $waitTime
 }
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )
# End Do Loop