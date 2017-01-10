#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

<#
.Synopsis
	Verify that demand changes with memory pressure inside the VM.

 Description:
	Verify that memory changes if multiple memory add/remove operations are done.
	Only 1 VM is required for this test.

   .Parameter vmName
    Name of the VM under test.

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case.

    .Example
    setupscripts\Runtime_Mem_MultipleAddRemove.ps1 -vmName nameOfVM -hvServer localhost -testParams 
    'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir; startupMem=2GB'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# Convert a string to int64 for use with the Set-VMMemory cmdlet
function ConvertToMemSize([String] $memString, [String]$hvServer)
{
    $memSize = [Int64] 0

    if ($memString.EndsWith("MB")){
        $num = $memString.Replace("MB","")
        $memSize = ([Convert]::ToInt64($num)) * 1MB
    }
    elseif ($memString.EndsWith("GB")){
        $num = $memString.Replace("GB","")
        $memSize = ([Convert]::ToInt64($num)) * 1GB
    }
    elseif( $memString.EndsWith("%")){
        $osInfo = Get-WMIObject Win32_OperatingSystem -ComputerName $hvServer
        if (-not $osInfo){
            "Error: Unable to retrieve Win32_OperatingSystem object for server ${hvServer}"
            return $False
        }

        $hostMemCapacity = $osInfo.FreePhysicalMemory * 1KB
        $memPercent = [Convert]::ToDouble("0." + $memString.Replace("%",""))
        $num = [Int64] ($memPercent * $hostMemCapacity)

        # Align on a 4k boundry
        $memSize = [Int64](([Int64] ($num / 2MB)) * 2MB)
    }
    # we received the number of bytes
    else{
        $memSize = ([Convert]::ToInt64($memString))
    }

    return $memSize
}

function checkStressNg([String]$conIpv4, [String]$sshKey)
{
    $cmdToVM = @"
#!/bin/bash
        command -v stress-ng
        sts=`$?
        exit `$sts
"@
    #"pingVMs: sendig command to vm: $cmdToVM"
    $filename = "CheckStress-ng.sh"

    # check for file
    if (Test-Path ".\${filename}"){
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # check the return Value of SendFileToVM
    if (-not $retVal){
        return $false
    }

    # execute command
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
}

# we need a scriptblock in order to pass this function to start-job
$scriptBlock = {
  # function for starting stress-ng
  function ConsumeMemory([String]$conIpv4, [String]$sshKey, [String]$rootDir)
  {

  # because function is called as job, setup rootDir and source TCUtils again
  if (Test-Path $rootDir){
    Set-Location -Path $rootDir
    if (-not $?){
      "Error: Could not change directory to $rootDir !"
      return $false
    }
    "Changed working directory to $rootDir"
  }
  else{
    "Error: RootDir = $rootDir is not a valid path"
    return $false
  }

  # Source TCUitls.ps1 for getipv4 and other functions
  if (Test-Path ".\setupScripts\TCUtils.ps1"){
    . .\setupScripts\TCUtils.ps1
    "Sourced TCUtils.ps1"
  }
  else{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
  }

      $cmdToVM = @"
#!/bin/bash
        __freeMem=`$(cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }')
        __freeMem=`$((__freeMem/1024))
        echo ConsumeMemory: Free Memory found `$__freeMem MB >> /root/HotAdd.log 2>&1
        __threads=8
        __chunks=`$((`$__freeMem / `$__threads))
        echo "Going to start `$__threads instance(s) of stress-ng every 2 seconds, each consuming 128MB memory" >> /root/HotAdd.log 2>&1
        stress-ng -m `$__threads --vm-bytes `${__chunks}M -t 120 --backoff 1500000
        echo "Waiting for jobs to finish" >> /root/HotAdd.log 2>&1
        wait
        exit 0
"@

    #"pingVMs: sendig command to vm: $cmdToVM"
    $filename = "ConsumeMem.sh"

    # check for file
    if (Test-Path ".\${filename}"){
      Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # check the return Value of SendFileToVM
    if (-not $retVal[-1]){
      return $false
    }

    # execute command as job
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
  }
}

#######################################################################
#
# Main script body
#
#######################################################################

#
# Check input arguments
#
if ($vmName -eq $null){
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null){
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null){
    "Error: testParams is null"
    return $False
}

# Write out test Params
$testParams

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# Name of first VM
$vm1Name = $null

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?){
  "Mandatory param RootDir=Path; not found!"
  return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir){
  Set-Location -Path $rootDir
  if (-not $?){
    "Error: Could not change directory to $rootDir !"
    return $false
  }
  "Changed working directory to $rootDir"
}
else{
  "Error: RootDir = $rootDir is not a valid path"
  return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1"){
  . .\setupScripts\TCUtils.ps1
}
else{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}

$params = $testParams.Split(";")
foreach ($p in $params){
    $fields = $p.Split("=")

    switch ($fields[0].Trim()){
      "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
      "ipv4"          { $ipv4       = $fields[1].Trim() }
      "sshKey"        { $sshKey     = $fields[1].Trim() }
      "startupMem"  { 
        $startupMem = ConvertToMemSize $fields[1].Trim() $hvServer

        if ($startupMem -le 0){
          "Error: Unable to convert startupMem to int64."
          return $false
        }
        "startupMem: $startupMem"
      }
    }

}

if (-not $sshKey){
  "Error: Please pass the sshKey to the script!"
  return $false
}

if (-not $startupMem){
  "Error: startupMem is not set!"
  return $false
}

# Delete any previous summary.log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue

if (-not $vm1){
  "Error: VM $vmName does not exist"
  return $false
}

# Check if stress-ng is installed
"Checking if stress-ng is installed"

$retVal = checkStressNg $ipv4 $sshKey

if (-not $retVal){
    "Error: dependency tool stress-ng is not installed!"
    return $false
}

"Stress-ng is installed! Will begin running memory stress tests shortly."

# Get memory stats from vm1
start-sleep -s 10
$sleepPeriod = 60

# get VM1 memory from host and guest
while ($sleepPeriod -gt 0){
  [int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
  [int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)

  [int64]$vm1BeforeIncrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
  "Free memory reported by guest VM before increase: $vm1BeforeIncrease"

  if ($vm1BeforeAssigned -gt 0 -and $vm1BeforeDemand -gt 0 -and $vm1BeforeIncrease -gt 0){
    break
  }

  $sleepPeriod-= 5
  start-sleep -s 5
}

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0 -or $vm1BeforeIncrease -le 0){
  "Error: vm1 $vmName reported 0 memory (assigned or demand)."
  return $False
}
"Memory stats after $vmName started reporting "
"  ${vmName}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

# Change 1 - Increase
$testMem = $startupMem + 2147483648

# Set new memory value
for ($i=0; $i -lt 3; $i++){
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem 
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB) 

    [int64]$vm1AfterIncrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    "Free memory reported by guest VM after increase: $vm1AfterIncrease KB"
    break
  }
}

if ( $i -eq 3 ){
  "Error: VM failed to change memory!"
  "LIS 4.1 or kernel version 4.4 required"
  return $false
}

if ( $vm1AfterAssigned -ne ($testMem/1MB)  ){
    "Error: Memory assigned doesn't match the memory set as parameter!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
    return $false
}

if ( ($vm1AfterIncrease - $vm1BeforeIncrease) -le 2000000){
    "Error: Guest reports that memory value hasn't increased enough!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: Initial Memory - $vm1BeforeIncrease KB :: After setting new value - $vm1AfterIncrease"
    return $false 
}
"Memory stats after $vmName memory was increased by 2GB "
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

# Change 2 - Decrease
Start-sleep -s 10
$testMem = $testMem - 2147483648

# Set new memory value
for ($i=0; $i -lt 3; $i++){
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem 
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB) 

    [int64]$vm1AfterDecrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    "Free memory reported by guest VM after decrease: $vm1AfterDecrease KB"
    break
  }
}

if ( $i -eq 3 ){
  "Error: VM failed to change memory!"
  "LIS 4.1 or kernel version 4.4 required"
  return $false
}

if ( $vm1AfterAssigned -ne ($testMem/1MB)  ){
    "Error: Memory assigned doesn't match the memory set as parameter!"
    "Memory stats after $vm1Name memory was changed "
    "  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
    return $false
}

if ( ($vm1AfterIncrease - $vm1AfterDecrease) -le 2000000){
    "Error: Guest reports that memory value hasn't decreased enough!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: Initial Memory - $vm1AfterIncrease KB :: After setting new value - $vm1AfterDecrease KB"
    return $false 
}
"Memory stats after $vmName memory was decreased by 2GB "
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

# Change 3 - Increase by 1GB
Start-sleep -s 10
$testMem = $testMem + 1073741824

# Set new memory value
for ($i=0; $i -lt 3; $i++){
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem 
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB) 

    [int64]$vm1AfterIncrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    "Free memory reported by guest VM guest VM after increase: $vm1AfterIncrease KB"
    break
  }
}

if ( $i -eq 3 ){
  "Error: VM failed to change memory!"
  "LIS 4.1 or kernel version 4.4 required"
  return $false
}

if ( $vm1AfterAssigned -ne ($testMem/1MB)  ){
    "Error: Memory assigned doesn't match the memory set as parameter!"
    "Memory stats after $vm1Name memory was changed "
    "  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
    return $false
}

if ( ($vm1AfterIncrease - $vm1AfterDecrease) -le 1000000){
    "Error: Guest reports that memory value hasn't increased enough!"
    "Memory stats after $vm1Name memory was changed "
    "  ${vmName}: Initial Memory - $vm1AfterDecrease KB :: After setting new value - $vm1AfterIncrease KB"
    return $false 
}
"Memory stats after $vmName memory was increased by 1GB "
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"


# Change 4 - Decrease by 2GB
Start-sleep -s 10
$testMem = $testMem - 2147483648
# Set new memory value
for ($i=0; $i -lt 3; $i++){
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem 
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB) 

    [int64]$vm1AfterDecrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    "Free memory reported by guest VM guest VM after increase: $vm1AfterDecrease KB"
    break
  }
}

if ( $i -eq 3 ){
  "Error: VM failed to change memory!"
  "LIS 4.1 or kernel version 4.4 required"
  return $false
}

if ( $vm1AfterAssigned -ne ($testMem/1MB)  ){
    "Error: Memory assigned doesn't match the memory set as parameter!"
    "Memory stats after $vm1Name memory was changed "
    "  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
    return $false
}

if ( ($vm1AfterIncrease - $vm1AfterDecrease) -le 2000000){
    "Error: Guest reports that memory value hasn't decreased enough!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: Initial Memory - $vm1AfterIncrease KB :: After setting new value - $vm1AfterDecrease KB"
    return $false 
}
"Memory stats after $vmName memory was decreased by 2GB "
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

# Send Command to consume
$job1 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir) ConsumeMemory $ip $sshKey $rootDir } -InitializationScript $scriptBlock -ArgumentList($ipv4,$sshKey,$rootDir)
if (-not $?){
  "Error: Unable to start job for creating pressure on $vmName"
  return $false
}

# sleep a few seconds so stress-ng starts and the memory assigned/demand gets updated
start-sleep -s 50

# get memory stats while stress-ng is running
[int64]$vm1Demand = ($vm1.MemoryDemand/1MB)
[int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
"Memory stats after $vmName started stress-ng"
"  ${vmName}: assigned - $vm1Assigned | demand - $vm1Demand"

if ($vm1Demand -le $vm1BeforeDemand){
  "Error: Memory Demand did not increase after starting stress-ng"
  return $false
}

# Wait for jobs to finish now and make sure they exited successfully
$timeout = 120
$firstJobStatus = $false
while ($timeout -gt 0){
  if ($job1.Status -like "Completed"){
    $firstJobStatus = $true
    $retVal = Receive-Job $job1
    if (-not $retVal[-1]){
      "Error: Consume Memory script returned false on VM1 $vmName"
      return $false
    }
    $diff = $totalTimeout - $timeout
    "Job finished in $diff seconds."
  }

  if ($firstJobStatus){
    break
  }

  $timeout -= 1
  start-sleep -s 1
}
start-sleep -s 5

# get memory stats after strss-ng stopped running
[int64]$vm1AfterStressAssigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1AfterStressDemand = ($vm1.MemoryDemand/1MB)
"Memory stats after $vmName stress-ng run"
"  ${vmName}: assigned - $vm1AfterStressAssigned | demand - $vm1AfterStressDemand"

if ($vm1AfterStressDemand -ge $vm1Demand){
  "Error: Memory Demand did not decrease after stress-ng stopped"
  return $false
}

"VM changed its memory and ran memory stress tests successfully!"
return $true