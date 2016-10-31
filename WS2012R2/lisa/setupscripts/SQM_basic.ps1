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
    Verify the basic SQM read operations work.
.Description
    Ensure the Data Exchange service is enabled for the VM and then
    verify if basic SQM data can be retrieved from vm.
    For SQM data to be retrieved, kvp process needs to be stopped on vm
    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>SQM_Basic</testName>
            <testScript>SetupScripts\SQM_Basic.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
            <testparams>
                <param>TC_COVERED=SQM-01</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to read intrinsic data from.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    setupScripts\SQM_Basic.ps1 -vmName "myVm" -hvServer "localhost -TestParams "rootDir=c:\lisa\trunk\lisa;TC_COVERED=SQM-01;sshKey=key;ipv4=ip"
.Link
    None.
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

#######################################################################
#
# KvpToDict
#
#######################################################################
function KvpToDict($rawData)
{
    <#
    .Synopsis
        Convert the KVP data to a PowerShell dictionary.
    .Description
        Convert the KVP xml data into a PowerShell dictionary.
        All keys are added to the dictionary, even if their
        values are null.
    .Parameter rawData
        The raw xml KVP data.
    .Example
        KvpToDict $myKvpData
    #>

    $dict = @{}

    foreach ($dataItem in $rawData)
    {
        $key = ""
        $value = ""
        $xmlData = [Xml] $dataItem
        
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name")
            {
                $key = $p.Value
            }

            if ($p.Name -eq "Data")
            {
                $value = $p.Value
            }
        }
        $dict[$key] = $value
    }

    return $dict
}

#######################################################################
#
# StopKVP
#
#######################################################################
function StopKVP([String]$conIpv4, [String]$sshKey, [String]$rootDir)
{
    $cmdToVM = @"
#!/bin/bash
    ps aux | grep kvp
    if [ `$? -ne 0 ]; then
      echo "KVP is already disabled" >> /root/StopKVP.log 2>&1
      exit 0
    fi

    kvpPID=`$(ps aux | grep kvp | awk 'NR==1{print `$2}')
    if [ `$? -ne 0 ]; then
        echo "Could not get PID of KVP" >> /root/StopKVP.log 2>&1
        exit 100
    fi

    kill `$kvpPID
    if [ `$? -ne 0 ]; then
        echo "Could not stop KVP process" >> /root/StopKVP.log 2>&1
        exit 100
    fi

    echo "KVP process stopped successfully"
    exit 0
"@
    $filename = "StopKVP.sh"

    # check for file
    if (Test-Path ".\${filename}")
    {
      Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${filename}"

    # check the return Value of SendFileToVM
    if (-not $retVal[-1])
    {
      return $false
    }

    # execute command as job
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
}

#######################################################################
#
# Main script body
#
#######################################################################
#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}
#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue
#
# Parse the test parameters
#
$rootDir = $null
$intrinsic = $True

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "nonintrinsic" { $intrinsic = $False }
    "rootdir"      { $rootDir   = $fields[1].Trim() }
    "ipv4"         { $ipv4      = $fields[1].Trim() }
    "SshKey"       { $sshKey    = $fields[1].Trim() }
    "TC_COVERED"   { $tcCovered = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    default  {}       
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

# Source TCUtils.ps1 for sendCommandToVM function
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
  . .\setupScripts\TCUtils.ps1
}
else
{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}

echo "Covers : ${tcCovered}" >> $summaryLog
#
# Verify the Data Exchange Service is enabled for this VM
#
$des = Get-VMIntegrationService -vmname $vmName -ComputerName $hvServer
if (-not $des)
{
    "Error: Unable to retrieve Integration Service status from VM '${vmName}'"
    return $False
}

$serviceEnabled = $False
foreach ($svc in $des)
{
    if ($svc.Name -eq "Key-Value Pair Exchange")
    {
        $serviceEnabled = $svc.Enabled
        break
    }
}

if (-not $serviceEnabled)
{
    "Error: The Data Exchange Service is not enabled for VM '${vmName}'"
    return $False
}
#
# Disable KVP on vm
#
$retVal = StopKVP $ipv4 $sshKey $rootDir
if (-not $retVal)
{
    "Failed to stop KVP process on VM"
    return $False
}
#
# Create a data exchange object and collect KVP data from the VM
#
$Vm = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$VMName`'"
if (-not $Vm)
{
    "Error: Unable to the VM '${VMName}' on the local host"
    return $False
}

$Kvp = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
if (-not $Kvp)
{
    "Error: Unable to retrieve KVP Exchange object for VM '${vmName}'"
    return $False
}

if ($Intrinsic)
{
    "Intrinsic Data"
    $kvpData = $Kvp.GuestIntrinsicExchangeItems
}
else
{
    "Non-Intrinsic Data"
    $kvpData = $Kvp.GuestExchangeItems
}

$dict = KvpToDict $kvpData
#
# Write out the kvp data so it appears in the log file
#
foreach ($key in $dict.Keys)
{
    $value = $dict[$key]
    Write-Output ("  {0,-27} : {1}" -f $key, $value)
}

if ($Intrinsic)
{
    $osInfo = GWMI Win32_OperatingSystem -ComputerName $hvServer
    if (-not $osInfo)
    {
        "Error: Unable to collect Operating System information"
        return $False
    }
    #
    # Create an array of key names specific to a build of Windows.
    #
    $osSpecificKeyNames = $null
    [System.Int32]$buildNR = $osInfo.BuildNumber

    if ($buildNR -ge 9600)
    {
        $osSpecificKeyNames = @("OSDistributionName", "OSDistributionData", "OSPlatformId","OSKernelVersion")
    }
    else {
        $osSpecificKeyNames = @("OSBuildNumber", "ServicePackMajor", "OSVendor", "OSMajorVersion",
                                "OSMinorVersion", "OSSignature")
    }
    $testPassed = $True
    foreach ($key in $osSpecificKeyNames)
    {
        if (-not $dict.ContainsKey($key))
        {
            "Error: The key '${key}' does not exist"
            $testPassed = $False
            break
        }
    }
}
else #Non-Intrinsic
{
    if ($dict.length -gt 0)
    {
        "Info: $($dict.length) non-intrinsic KVP items found"
        $testPassed = $True
    }
    else
    {
        "Error: No non-intrinsic KVP items found"
        $testPassed = $False
    }
}

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

return $testPassed