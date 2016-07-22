################################################################################
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
################################################################################

<#
.Synopsis
    This is a setup script that will run before the VM is booted.
    The script will create two .vhdx files and attach and detached them, one at a time.


.Description
     This is a setup script that will run before the VM is booted.
     The script will create two .vhdx files and attach and detached them, one at a time.
     The first .vhdx file will be attached and dettached, then the second .vhdx
     file will be attached and dettached and then the first .vhdx file will be attached
     again,  will do add/remove two disks based on LoopCount parameter.
     The VM should recognize the first .vhdx file.

    The  scripts will always pass the vmName, hvServer, and a string of
    testParams from the test definition separated by semicolons. The testParams
    for this script identifies the two VHDx types, two sector sizes and the two
    default sizes of the .vhdx files which will be created.

    The following are some examples:

    "Type1=Dynamic;SectorSize1=512;DefaultSize1=5GB;
    Type2=Dynamic;SectorSize2=512;DefaultSize2=2GB":
    Create 2 VHDx; first .vhdx file will be a 5GB, 512 sector size, dynamic VHDx
    and the second .vhdx file will be a 2GB, 512 sector size, dynamic VHDx

    Test params xml entry:
    <testparams>
        <param>TC_COVERED=Something-01</param>
        <param>Type1=Dynamic</param>
        <param>SectorSize1=512</param>
        <param>DefaultSize1=5GB</param>
        <param>Type2=Dynamic</param>
        <param>SectorSize2=512</param>
        <param>DefaultSize2=2GB</param>
        <param>LoopCount=2</param>
     </testparams>

.Parameter vmName
    Name of the VM to add disk to.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\STOR_unPlug_Plug.ps1 `
    -vmName VM_NAME
    -hvServer HYPERV_SERVER `
    -testParams "Type1=Dynamic;SectorSize1=512;DefaultSize1=5GB;Type2=Dynamic;SectorSize2=512;DefaultSize2=2GB;LoopCount=2"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

################################################################################
# NewVHDxPath
#
# Description
#   Returns the path of a .vhdx created with CreateVHDxDiskDrive function
################################################################################
function NewVHDxPath([string] $vmName, [string] $hvServer)
{
    $vmDrive = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer
    $lastSlash = $vmDrive[0].Path.LastIndexOf("\")
    if (-not $vhdPath)
    {
        $defaultVhdPath = $vmDrive[0].Path.Substring(0,$lastSlash)
    }
    else {
        $defaultVhdPath = $vhdPath
    }
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }
        return $defaultVhdPath
}

################################################################################
# AttachVHDxDiskDrive
#
# Description
#   Attaches .vhdx hard-disk to the VM.
################################################################################
function AttachVHDxDiskDrive( [string] $vmName, [string] $hvServer,
                        [string] $vhdxPath, [string] $controllerType)
{
    Add-VMHardDiskDrive -VMName $vmName `
                            -Path $vhdxPath `
                            -ControllerType $controllerType `
                            -ComputerName $hvServer

    if ($error.Count -gt 0)
    {
        Write-Output "Error: Add-VMHardDiskDrive failed to add drive on SCSI controller $error[0].Exception"
        $error[0].Exception
        return $False
    }
    $error.Clear()
    return $True
}


function RemoveVHDxDiskDrive( [string] $vmName, [string] $hvServer,
                        [string] $vhdxPath, [string] $controllerType)
{
    Remove-VMHardDiskDrive -VMName $vmName `
                            -Path $vhdxPath `
                            -ControllerType $controllerType `
                            -ComputerName $hvServer

    if ($error.Count -gt 0)
    {
        Write-Output "Error: Remove-VMHardDiskDrive failed to remove drive on SCSI controller $error[0].Exception"
        $error[0].Exception
        return $False
    }
    $error.Clear()
    return $True
}

################################################################################
#
# Main script
#
################################################################################

#
# Set default values
#
$retVal = $False
$sectorSize1 = $null
$sectorSize2 = $null
$defaultSize1 = 2GB
$defaultSize2 = 1GB

# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Check input arguments
#
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    Write-Output "Error: VM name is null"| Tee-Object -Append -file $summaryLog
    return $False
}
if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    Write-Output "Error: hvServer is null"| Tee-Object -Append -file $summaryLog
    return $False
}
if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    Write-Output "Error: setupScript requires test params"| Tee-Object -Append -file $summaryLog
    return $False
}

#
# Parse the testParams string
#
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()
    switch ($fields[0].Trim())
{
    "Type1"          { $type1    = $fields[1].Trim() }
    "SectorSize1"    { $sectorSize1    = $fields[1].Trim() }
    "DefaultSize1"   { $defaultSize1  = $fields[1].Trim() }
    "Type2"          { $type2    = $fields[1].Trim() }
    "SectorSize2"    { $sectorSize2    = $fields[1].Trim() }
    "DefaultSize2"   { $defaultSize2  = $fields[1].Trim() }
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "LoopCount" { $loopCount = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

if (-not (Test-Path $rootDir)) {
    Write-Output "Error: The directory `"${rootDir}`" does not exist"| Tee-Object -Append -file $summaryLog
    return $False
}


cd $rootDir

$numb = (Get-VMScsiController -VMName $vmName -ComputerName $hvServer).ControllerNumber.Count - 1
$p = "scsi=" + $numb + ",1," + $type2 + "," + $sectorSize2

####
$path1 = NewVHDxPath $vmName $hvServer
$path2 =  $path1 + $vmName + "-" + $defaultSize2 + "-" + $sectorSize2 + "-test.vhdx"
$path1 +=  $vmName + "-" + $defaultSize1 + "-" + $sectorSize1 + "-test.vhdx"



for ($i=0; $i -lt $loopCount; $i++)
{

  # Remove the 1st VHDx
  #
  Write-Output "Current loop number is $i."
  $retVal = RemoveVHDxDiskDrive $vmName $hvServer $path1 SCSI

  if (-not $retVal)
  {
      Write-Output "Error: Failed to remove VHDx with size $defaultSize1"| Tee-Object -Append -file $summaryLog
      return $False
  }
  Write-Output "Removed VHDx with size $defaultSize1"


  $retVal = RemoveVHDxDiskDrive $vmName $hvServer $path2 SCSI

  if (-not $retVal)
  {
      Write-Output "Error: Failed to remove VHDx with size $defaultSize2"| Tee-Object -Append -file $summaryLog
      return $False
  }
  Write-Output "Removed VHDx with size $defaultSize2"

  $sts = RunRemoteScript "STOR_hot_remove.sh"
  if (-not $sts[-1])
  {
      Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
      Write-Output "ERROR: Running $remoteScript script failed on VM!"
      return $False
  }

  #
  # Attaching the 1st VHDx again
  #
  $retVal = AttachVHDxDiskDrive $vmName $hvServer $path1 SCSI

  if (-not $retVal)
  {
      Write-Output "Error: Failed to attach VHDx with size $defaultSize1"| Tee-Object -Append -file $summaryLog
      return $False
  }
  Write-Output "Attached VHDx with size $defaultSize1"


  $retVal = AttachVHDxDiskDrive $vmName $hvServer $path2 SCSI

  if (-not $retVal)
  {
      Write-Output "Error: Failed to attach VHDx with size $defaultSize2"| Tee-Object -Append -file $summaryLog
      return $False
  }
  Write-Output "Attached VHDx with size $defaultSize2"


  $diskNumber = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l | grep 'Disk /dev/sd*' | grep -v 'Disk /dev/sda' | wc -l"
  if ( $diskNumber -ne 2)
  {
    Write-Output "Error: Failed to attach VHDx "| Tee-Object -Append -file $summaryLog
    return $False
  }
}


return $true
