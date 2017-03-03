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

#####################################################################
#
# This test will check the time sync of guest OS with the host. 
# It will save the state of the VM.
# It will then wait for 10 mins, start the VM from saved state and will re-check the time sync.
# 
# testParams
#    HOME_DIR=C:\lisa\
#    ipv4=
#    sshKey=
#
# now=`date "+%m/%d/%Y %H:%M:%S%p"
# returns 04/27/2012 16:10:30PM
#
#####################################################################

param ([String] $vmName, [String] $hvServer, [String] $testParams)

$sshKey = $null
$ipv4 = $null
$rootDir = $null

#####################################################################
#
# SendCommandToVM()
#
#####################################################################
function SendCommandToVM([String] $sshKey, [String] $ipv4, [string] $command)
{
    $retVal = $null

    $sshKeyPath = Resolve-Path $sshKey
    
    $dt = .\bin\plink.exe -i ${sshKeyPath} root@${ipv4} $command
    if ($?)

    {
        $retVal = $dt
    }
    else
    {
        Write-Output "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    return $retVal
}

#####################################################################
#
#   GetUnixVMTime()
#
#####################################################################
function GetUnixVMTime([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }

    $unixTimeStr = $null
    $command = 'date "+%m/%d/%Y/%T" -u'

    $unixTimeStr = SendCommandToVM ${sshKey} $ipv4 $command
    if (-not $unixTimeStr -and $unixTimeStr.Length -lt 20)
    {
        return $null
    }
    
    return $unixTimeStr
}

#####################################################################
#
#   GetTimeSync()
#
#####################################################################
function GetTimeSync([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }
    #
    # Get a time string from the VM, then convert the Unix time string into a .NET DateTime object
    #
    $unixTimeStr = GetUnixVMTime -sshKey "ssh\${sshKey}" -ipv4 $ipv4
    if (-not $unixTimeStr)
    {
       "Error: Unable to get date/time string from VM"
        return $False
    }

    $pattern = 'MM/dd/yyyy/HH:mm:ss'
    $unixTime = [DateTime]::ParseExact($unixTimeStr, $pattern, $null)

    #
    # Get our time
    #
    $windowsTime = [DateTime]::Now.ToUniversalTime()

    #
    # Compute the timespan, then convert it to the absolute value of the total difference in seconds
    #
    $diffInSeconds = $null
    $timeSpan = $windowsTime - $unixTime
    if ($timeSpan)
    {
        $diffInSeconds = [Math]::Abs($timeSpan.TotalSeconds)
    }

    #
    # Display the data
    #
    "Windows time: $($windowsTime.ToString())"
    "Unix time: $($unixTime.ToString())"
    "Difference: $diffInSeconds"

     Write-Output "Time difference = ${diffInSeconds}" | Out-File -Append $summaryLog
     return $diffInSeconds
}

#####################################################################
#
# Main script body
#
#####################################################################
$retVal = $False

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

#
# Parse the testParams string
#
$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        # Just ignore it
        continue
    }
    
    $val = $tokens[1].Trim()
    
    switch($tokens[0].Trim().ToLower())
    {
    "sshkey"  { $sshKey = $val }
    "ipv4"    { $ipv4 = $val }
    "rootdir" { $rootDir = $val }
    "TestLogDir"  { $TestLogDir  = $val }
    "TestName"   { $TestName     = $val }
    default  { continue }
    }
}

#
# Make sure the required testParams were found
#
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

if (-not $ipv4)
{
    "Error: testParams is missing the ipv4 parameter"
    return $False
}

#
# Change the working directory
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC34" | Out-File -Append $summaryLog

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4

$msg = "Error: Test case failed!"
if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    $msg = "Info: Time is properly synced"
    $retVal = $true
}

$msg

#
# Save the VM state and wait for 10 mins. 
#
Save-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
if ($? -ne "True")
{
  write-host "Error while saving the VM state"
  return $false
}

Start-Sleep -seconds 600

#
# After 10 mins start the VM and check the time sync.
#
Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
if ($? -ne "True")
{
  write-host "Error while starting the VM from saved state"
  return $false
}

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4

$msg = "Error: Test case failed!"
if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    $msg = "Info: After start from save state, time is properly synced"
    $retVal = $true
}

Write-Output $msg | Out-File $summaryLog

#
# Collect the log file from the client
#

$remoteFile = "gcov_data.zip"
$localFile = "${TestLogDir}\${vmName}_${TestName}_gcov_data.zip"
"Info: Collect gcov_data.zip from ${remoteFile} to ${localFile}"
bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteFile} .
$sts = $?
if ($sts)
{
    if (test-path $remoteFile)
    {
        $contents = Get-Content -Path $remoteFile
        if ($null -ne $contents)
        {
                if ($null -ne ${TestLogDir})
                {
                    move "${remoteFile}" "${localFile}"
}}}}

return $retVal
