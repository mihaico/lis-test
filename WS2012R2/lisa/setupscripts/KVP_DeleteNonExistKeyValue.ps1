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
    Try to Delete a Non-Exist KVP item from a Linux guest.
.Description
    Try to Delete a Non-Exist KVP item from pool 0 on a Linux guest.
   
.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\KVP_DeleteNonExistKeyValue.ps1 -vmName "myVm" -hvServer "localhost -TestParams "key=aaa;value=222"

.Link
    None.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$key = $null
$value = $null
$rootDir = $null
$tcCovered = "Unknown"

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $False
}

if (-not $testParams)
{
    "Error: No testParams provided"
    "     : This script requires key & value test parameters"
    return $False
}

#
# Find the testParams we require.  Complain if not found
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "key"        { $key       = $fields[1].Trim() }
    "sshKey" { $sshKey = $fields[1].Trim() }
    "ipv4"         { $ipv4      = $fields[1].Trim() }
    "value"      { $value     = $fields[1].Trim() }
    "rootDir"    { $rootDir   = $fields[1].Trim() }
    "tc_covered" { $tcCovered = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
} 

"Info : Checking for required test parameters"

if (-not $key)
{
    "Error: Missing testParam Key to be added"
    return $False
}

if (-not $value)
{
    "Error: Missing testParam Value to be added"
    return $False
}

if (-not $rootDir)
{
    "Warn : no rootDir test parameter specified"
}
else
{
    cd $rootDir
}

#
# Creating the summary file
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File -Append $summaryLog

#
# Delete the Non-Existing Key Value pair from the Pool 0 on guest OS. If the Key is already present, will return proper message.
#
"Info : Creating VM Management Service object"
$VMManagementService = Get-WmiObject -ComputerName $hvServer -class "Msvm_VirtualSystemManagementService" -namespace "root\virtualization\v2"
if (-not $VMManagementService)
{
    "Error: Unable to create a VMManagementService object"
    return $False
}

$VMGuest = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName='$VmName'"
if (-not $VMGuest)
{
    "Error: Unable to create VMGuest object"
    return $False
}

"Info : Creating Msvm_KvpExchangeDataItem object"

$Msvm_KvpExchangeDataItemPath = "\\$hvServer\root\virtualization\v2:Msvm_KvpExchangeDataItem"
$Msvm_KvpExchangeDataItem = ([WmiClass]$Msvm_KvpExchangeDataItemPath).CreateInstance()
if (-not $Msvm_KvpExchangeDataItem)
{
    "Error: Unable to create Msvm_KvpExchangeDataItem object"
    return $False
}
"Info : Detecting Host version of Windows Server"
$osInfo = GWMI Win32_OperatingSystem -ComputerName $hvServer
if (-not $osInfo)
{
    "Error: Unable to collect Operating System information"
    return $False
}

"Info : Deleting Key '${key}' from Pool 0"

$Msvm_KvpExchangeDataItem.Source = 0
$Msvm_KvpExchangeDataItem.Name = $Key
$Msvm_KvpExchangeDataItem.Data = $Value
$result = $VMManagementService.RemoveKvpItems($VMGuest, $Msvm_KvpExchangeDataItem.PSBase.GetText(1))
$job = [wmi]$result.Job

while($job.jobstate -lt 7) {
	$job.get()
} 
Write-Output $job.ErrorCode
Write-Output $job.Status
#
# Due to a change in behavior between Windows Server versions, we need to modify
# acceptance criteria based on the version of the HyperVisor.
#
[System.Int32]$buildNR = $osInfo.BuildNumber

. .\setupscripts\TCUtils.ps1
# Collect gcov
RunRemoteScript "collect_gcov_data.sh"

$remoteFile = "gcov_data.zip"
$localFile = "${TestLogDir}\${vmName}_${TestName}_gcov_data.zip"
.\bin\pscp -i ssh\${sshKey} root@${ipv4}:${remoteFile} .
$sts = $?
if ($sts)
{
    "Info: Collect gcov_data.zip from ${remoteFile} to ${localFile}"
    if (test-path $remoteFile)
    {
        $contents = Get-Content -Path $remoteFile
        if ($null -ne $contents)
        {
                if ($null -ne ${TestLogDir})
                {
                    move "${remoteFile}" "${localFile}"
}}}}
if ($buildNR -ge 9600)
{
    if ($job.ErrorCode -eq 0)
    {
        "Info : Windows Server returns success even when the KVP item does not exist"
        return $True
    }
    "Error: RemoveKVPItems() returned error code $($job.ErrorCode)"
    return $False
}
elseIf ($buildNR -ge 9200)
{
    if ($job.ErrorCode -eq 32773)
    {
        "Info : RemoveKvpItems() correctly returned 32773"

        return $True
    }
    "Error: RemoveKVPItems() returned error code $($job.ErrorCode) rather than 32773"
    return $False
}
else {
    "Error: Unsupported build of Windows Server"
    return $False
}