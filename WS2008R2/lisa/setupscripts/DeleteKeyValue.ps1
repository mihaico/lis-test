########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################


<#
.Synopsis
    

.Description
    This PowerShell test case script deletes a key value pair from the KVP Pool 0 on guest OS.
    Returns a proper error message if the key is not present.           

   This test case should be run after the KVP Basic test & "HostCanWriteKVPToOnly_P0" test.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null"
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

if (-not $testParams)
{
    "Error: No testParams provided"
    "This script requires the Key & value as the test parameters"
    return $retVal
}

#
# Find the testParams we require.  Complain if not found
#
$Key = $null
$Value = $null
$rootDir = $null
$TC_COVERED = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "Key")
    {
        $Key = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "Value")
    {
        $Value = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "RootDir")
    {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TC_COVERED")
    {
        $TC_COVERED = $fields[1].Trim()
    }
            
}

if (-not $Key)
{
    "Error: Missing testParam Key to be added"
    return $retVal
}
if (-not $Value)
{
    "Error: Missing testParam Value to be added"
    return $retVal
}

#
# creating the summary file
#
cd $rootDir
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${TC_COVERED}" | Out-File -Append $summaryLog



#
# Import the HyperV module
#

$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
   Import-module .\HyperVLibV2Sp1\Hyperv.psd1 
}

#
# Delete the Key Value pair from the Pool 0 on guest OS. If the Key is already not present, will return proper message.
#

$VMManagementService = Get-WmiObject -class "Msvm_VirtualSystemManagementService" -namespace "root\virtualization" -ComputerName $hvServer
$VMGuest = Get-WmiObject -Namespace root\virtualization -ComputerName $hvServer -Query "Select * From Msvm_ComputerSystem Where ElementName='$VmName'"
$Msvm_KvpExchangeDataItemPath = "\\$hvServer\root\virtualization:Msvm_KvpExchangeDataItem"
$Msvm_KvpExchangeDataItem = ([WmiClass]$Msvm_KvpExchangeDataItemPath).CreateInstance()
$Msvm_KvpExchangeDataItem.Source = 0

$tmp = $Msvm_KvpExchangeDataItem.PSBase.GetText(1)

write-output "Deleting Key value pair from Pool 0" $key, $Value

$Msvm_KvpExchangeDataItem.Name = $Key
$Msvm_KvpExchangeDataItem.Data = $Value
$result = $VMManagementService.RemoveKvpItems($VMGuest, $Msvm_KvpExchangeDataItem.PSBase.GetText(1))
$job = [wmi]$result.Job

while($job.jobstate -lt 7) {
	$job.get()
} 

if ($job.ErrorCode -ne 0)
{
  write-host "Error while deleting the key value pair"
  if ($job.ErrorCode -eq 32773)
  {  
    Write-Output "VMManagementService.RemoveKvpItems() returned an error. Non-existing key cannot be deleted Error Code-" $job.ErrorCode | Out-File -Append $summaryLog
    $retVal = $true
    return $retVal
  }
  else
  {
  Write-Output "Delete key value failed -Job error code" $job.ErrorCode | Out-File -Append $summaryLog
  return $retVal
  }
}

Write-Output $job.JobStatus
$retVal = $true
Write-Output "Key value pair is found and got successfully deleted from Pool0 on guest" | Out-File -Append $summaryLog
return $retVal

