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
 Description:
   This script tests the VM's Heartbeat after the VM enters in PausedCritical state.
   For the VM to enter in PausedCritical state the disk where the VHD is has to be full.
   We create a new partition, copy the VHD and fill up the partition.
   After the VM enters in PausedCritical state we free some space and the VM
   should return to normal OK Heartbeat.

   .Parameter vmName
    Name of the VM to configure.
    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    .Parameter testParams
    Test data for this test case
    .Example
    setupScripts\PausedCritical.ps1 -vmName vm -hvServer localhost -testParams "DriveLetter=Z:;vhdpath=C:\TestVolume.vhdx;"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
# To Get Parent VHD from VM.
#######################################################################
function GetParentVHD($vmName, $hvServer)
{
    $ParentVHD = $null

    $VmInfo = Get-VM -Name $vmName -ComputerName $hvServer
    if (-not $VmInfo)
        {
             Write-Error -Message "Error: Unable to collect VM settings for ${vmName}" -ErrorAction SilentlyContinue
             return $False
        }

    if ( $VmInfo.Generation -eq "" -or $VmInfo.Generation -eq 1  )
        {
            $Disks = $VmInfo.HardDrives
            foreach ($VHD in $Disks)
                {
                    if ( ($VHD.ControllerLocation -eq 0 ) -and ($VHD.ControllerType -eq "IDE"  ))
                        {
                            $Path = Get-VHD $VHD.Path -ComputerName $hvServer
                            if ([string]::IsNullOrEmpty($Path.ParentPath))
                                {
                                    $ParentVHD = $VHD.Path
                                }
                            else{
                                    $ParentVHD =  $Path.ParentPath
                                }

                            Write-Host "Parent VHD Found: $ParentVHD "
                        }
                }
        }
    if ( $VmInfo.Generation -eq 2 )
        {
            $Disks = $VmInfo.HardDrives
            foreach ($VHD in $Disks)
                {
                    if ( ($VHD.ControllerLocation -eq 0 ) -and ($VHD.ControllerType -eq "SCSI"  ))
                        {
                            $Path = Get-VHD $VHD.Path -ComputerName $hvServer
                            if ([string]::IsNullOrEmpty($Path.ParentPath))
                                {
                                    $ParentVHD = $VHD.Path
                                }
                            else{
                                    $ParentVHD =  $Path.ParentPath
                                }
                            Write-Host "Parent VHD Found: $ParentVHD "
                        }
                }
        }

    if ( -not ($ParentVHD.EndsWith(".vhd") -xor $ParentVHD.EndsWith(".vhdx") ))
    {
         Write-Error -Message " Parent VHD is Not correct please check VHD, Parent VHD is: $ParentVHD " -ErrorAction SilentlyContinue
         return $False
    }

    return $ParentVHD

}


function CreateChildVHD($ParentVHD, $defaultpath)
{
    $ChildVHD  = $null

    $hostInfo = Get-VMHost -ComputerName $hvServer
    if (-not $hostInfo)
    {
         Write-Error -Message "Error: Unable to collect Hyper-V settings for ${hvServer}" -ErrorAction SilentlyContinue
         return $False
    }

    if (-not $defaultpath.EndsWith("\"))
    {
        $defaultpath += "\"
    }

    # Create Child VHD

    if ($ParentVHD.EndsWith("x") )
    {
        $ChildVHD = $defaultpath+$vmName+"-child.vhdx"

    }
    else
    {
        $ChildVHD = $defaultpath+$vmName+"-child.vhd"
    }

    if ( Test-Path $ChildVHD )
    {
        Write-Host "Deleting existing VHD $ChildVHD"
        del $ChildVHD
    }

    # Copy Child VHD

    Copy-Item $ParentVHD $ChildVHD
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to create child VHD"  -ErrorAction SilentlyContinue
       return $False
    }

    return $ChildVHD

}

function Cleanup()
{
    Write-Output "Starting cleanup"
    # Clean up
    $sts = Stop-VM -Name $vmName1 -ComputerName $hvServer -TurnOff
    if (-not $?)
    {
       Write-Output "Error: Unable to Shut Down VM $vmName1"

    }

    # Delete New VM created
    $sts = Remove-VM -Name $vmName1 -ComputerName $hvServer -Confirm:$false -Force
    if (-not $?)
    {
      Write-Output "Error: Deleting New VM $vmName1"
    }

    # Delete partition
    Dismount-VHD -Path $vhdpath -ComputerName $hvServer

    # Detele VHD
    del $vhdpath
}


#######################################################################
#
# Main script body
#
#######################################################################

$ipv4vm1 = $null
$retVal = $true

$summaryLog  = "${vmName}_summary.log"
$vmName1 = "${vmName}_ChildVM"

# Check input arguments
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

$params = $testParams.Split(';')
foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
    "rootDir" { $rootDir = $fields[1].Trim() }
    "driveletter" { $driveletter = $fields[1].Trim() }
    "TC_COVERED" { $tcCovered = $fields[1].Trim() }
    "vhdpath" { $vhdpath = $fields[1].Trim() }
     default  {}
    }
}

if ($null -eq $sshKey)
{
    "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    "ERROR: Test parameter driveletter was not specified."
    return $False
}

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${tcCovered}" | Tee-Object -Append -file $summaryLog

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# Shutdown gracefully so we dont corrupt VHD.
Stop-VM -Name $vmName -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Unable to Shut Down VM" | Tee-Object -Append -file $summaryLog
    return $False
}

# Get Parent VHD
$ParentVHD = GetParentVHD $vmName $hvServer
if(-not $ParentVHD)
{
    Write-Output "Error getting Parent VHD of VM $vmName" | Tee-Object -Append -file $summaryLog
    return $False
}

# Get VHD size
$VHDSize = (Get-VHD -Path $ParentVHD -ComputerName $hvServer).FileSize
[uint64]$newsize = [math]::round($VHDSize /1Gb, 1)
$newsize = ($newsize * 1GB) + 1GB

if ( Test-Path $vhdpath )
{
    Write-Host "Deleting existing VHD $vhdpath"
    del $vhdpath
}

# Create the new partition
New-VHD -Path $vhdpath -Dynamic -SizeBytes $newsize -ComputerName $hvServer | Mount-VHD -Passthru | Initialize-Disk -Passthru |
New-Partition -DriveLetter $driveletter[0] -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -Force
if (-not $?)
{
    Write-Output "Error: Failed to create the new partition $driveletter" | Tee-Object -Append -file $summaryLog
}

# Copy parent VHD to partition
$ChildVHD = CreateChildVHD $ParentVHD $driveletter
if(-not $ChildVHD)
{
    Write-Output "Error: Creating Child VHD of VM $vmName" | Tee-Object -Append -file $summaryLog
    return $False
}

$vm = Get-VM -Name $vmName -ComputerName $hvServer

# Get the VM Network adapter so we can attach it to the new VM
$VMNetAdapter = Get-VMNetworkAdapter $vmName -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Get-VMNetworkAdapter" | Tee-Object -Append -file $summaryLog
    return $false
}

#Get VM Generation
$vm_gen = $vm.Generation

# Remove old VM
Remove-VM -Name $vmName1 -ComputerName $hvServer -Confirm:$false -Force

# Create the ChildVM
$newVm = New-VM -Name $vmName1 -ComputerName $hvServer -VHDPath $ChildVHD -MemoryStartupBytes 1024MB -SwitchName $VMNetAdapter[0].SwitchName -Generation $vm_gen
if (-not $?)
{
   Write-Output "Error: Creating New VM $vmName1" | Tee-Object -Append -file $summaryLog
   return $False
}

# Disable secure boot
if ($vm_gen -eq 2)
{
    Set-VMFirmware -VMName $vmName1 -ComputerName $hvServer -EnableSecureBoot Off
    if(-not $?)
    {
        Write-Output "Error: Unable to disable secure boot" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

Write-Output "Info: Child VM $vmName1 created"

$timeout = 300
$sts = Start-VM -Name $vmName1 -ComputerName $hvServer
if (-not (WaitForVMToStartKVP $vmName1 $hvServer $timeout ))
{
    Write-Output "Error: ${vmName1} failed to start" | Tee-Object -Append -file $summaryLog
    return $False
}
Write-Output "Info: New VM $vmName1 started"

# Get the VM1 ip
$ipv4vm1 = GetIPv4 $vmName1 $hvServer

# Get partition size
$disk = Get-WmiObject Win32_LogicalDisk -ComputerName $hvServer -Filter "DeviceID='${driveletter}'" | Select-Object FreeSpace

$filesize = $disk.FreeSpace - 100000
$file_path_formatted = $driveletter[0] + '$\' + 'testfile'

# Fill up the partition
$createfile = fsutil file createnew \\$hvServer\$file_path_formatted $filesize
if ($createfile -notlike "File *testfile* is created")
{
    Write-Output "Error: Could not create the sample test file in the working directory! $file_path_formatted" | Tee-Object -Append -file $summaryLog
    Cleanup
    return $False
}
Write-Output "Info: Created test file on \\$hvServer\$file_path_formatted with the size $filesize" | Tee-Object -Append -file $summaryLog

$retVal = SendCommandToVM $ipv4vm1 $sshKey "dd if=/dev/urandom of=/root/data2 bs=1M count=500 2>/dev/null &"
if (-not $?)
{
    Write-Output "Error: Could not send command to vm $vmName1" | Tee-Object -Append -file $summaryLog
}
Start-Sleep 20

$vm1 = Get-VM -Name $vmName1 -ComputerName $hvServer
if ($vm1.State -ne "PausedCritical")
{
    Write-Output "Error: VM $vmName1 is not in Paused-Critical after we filled the disk" | Tee-Object -Append -file $summaryLog
    Cleanup
    return $False
}
Write-Output "Info: VM $vmName1 entered in Paused-Critical state, as expected" | Tee-Object -Append -file $summaryLog

# Create space on partition
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if (-not $?) {
    Write-Output "ERROR: Cannot remove the test file '${testfile1}'!" | Tee-Object -Append -file $summaryLog
    Cleanup
    return $False
}
Write-Output "Info: Test file deleted from mounted VHDx" | Tee-Object -Append -file $summaryLog

# Resume VM after we created space on the partition
Resume-VM -Name $vmName1 -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Failed to resume the vm $vmName1" | Tee-Object -Append -file $summaryLog
}

# Check Heartbeat
Start-Sleep 10
if ($vm1.Heartbeat -eq "OkApplicationsUnknown")
{
    "Info: Heartbeat detected, status OK."
    Write-Output "Info: Test Passed. Heartbeat is again reported as OK." | Tee-Object -Append -file $summaryLog
}
else
{
    Write-Output "Error: Heartbeat is not in the OK state." | Out-File -Append $summaryLog
    Cleanup
    return $False
}

Cleanup

return $retVal
