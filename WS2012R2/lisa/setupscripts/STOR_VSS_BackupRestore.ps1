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
    This script tests VSS backup functionality.

.Description
    This script will create a file on the vm, backs up the VM,
    deletes the file and restores the VM.

    It uses a second partition as target.

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available.

    The .xml entry for this script could look like either of the
    following:

    An actual testparams definition may look like the following

        <testParams>
            <param>driveletter=F:</param>
        <testParams>

    A typical XML definition for this test case would look similar
    to the following:
        <test>
        <testName>VSS_BackupRestore</testName>
            <testScript>setupscripts\VSS_BackupRestore.ps1</testScript>
            <testParams>
                <param>driveletter=F:</param>
                <param>TC_COVERED=VSS-06,VSS-17</param>
            </testParams>
            <timeout>1200</timeout>
            <OnError>Continue</OnError>
        </test>

.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_WSB_BackupRestore.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
# Check boot.msg in Linux VM for Recovering journal.
#######################################################################
function CheckRecoveringJ()
{
    $retValue = $False

    .\bin\pscp -i ssh\${sshKey}  root@${ipv4}:/var/log/boot.* ./boot.msg

    if (-not $?)
    {
      Write-Output "ERROR: Unable to copy boot.msg from the VM"
       return $False
    }

    $filename = ".\boot.msg"
    $text = "recovering journal"

    $file = Get-Content $filename
    if (-not $file)
    {
        Write-Error -Message "Unable to read file" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

     foreach ($line in $file)
    {
        if ($line -match $text)
        {
            $retValue = $True
            Write-Output "$line"
        }
    }

    del $filename
    return $retValue
}

#######################################################################
# Create a file on the VM.
#######################################################################
function CreateFile()
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "echo abc > /root/1"
    if (-not $?)
    {
        Write-Error -Message "ERROR: Unable to create file" -ErrorAction SilentlyContinue
        return $False
    }

    return  $True
}

#######################################################################
# Delete a file on the VM.
#######################################################################
function DeleteFile()
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "rm -rf /root/1"
    if (-not $?)
    {
        Write-Error -Message "ERROR: Unable to delete file" -ErrorAction SilentlyContinue
        return $False
    }

    return  $True
}

#######################################################################
# Checks if test file is present or not.
#######################################################################
function CheckFile()
{
    Write-Output "the sshKey is ${sshKey}, the IP is ${ipv4}"
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "cat /root/1"
    if (-not $?)
    {
        Write-Error -Message "ERROR: Unable to read file" -ErrorAction SilentlyContinue
        Write-Output "================================"
        return $False
    }

    return  $True
}

#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

Write-Output "Removing old backups"
try { Remove-WBBackupSet -Force -WarningAction SilentlyContinue }
Catch { Write-Output "No existing backup's to remove"}

# Define and cleanup the summaryLog
$summaryLog  = "${vmName}_summary.log"
echo "Covers VSS Backup" > $summaryLog

# Check input arguments
if ($vmName -eq $null)
{
    "ERROR: VM name is null"
    return $retVal
}

# Check input params
$params = $testParams.Split(";")

foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey = $fields[1].Trim() }
    "ipv4" { $ipv4 = $fields[1].Trim() }
    "rootdir" { $rootDir = $fields[1].Trim() }
    "driveletter" { $driveletter = $fields[1].Trim() }
    "secureBootVM" { $testSecureBootVM = [System.Convert]::ToBoolean($fields[1].Trim()) }
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

if ($null -eq $rootdir)
{
    "ERROR: Test parameter rootdir was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    "Warning: Backup driveletter is not specified."
    return $False
}

echo $params

# Change the working directory to where we need to be
cd $rootDir

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# Check if the Vm VHD in not on the same drive as the backup destination
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: VM '${vmName}' does not exist"
    return $False
}

foreach ($drive in $vm.HardDrives)
{
    if ( $drive.Path.StartsWith("${driveLetter}"))
    {
        "Error: Backup partition '${driveLetter}' is same as partition hosting the VMs disk"
        "       $($drive.Path)"
        return $False
    }
}

# Send utils.sh to VM
echo y | .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\utils.sh root@${ipv4}:
if (-not $?)
{
    Write-Output "ERROR: Unable to copy utils.sh to the VM"
    return $False
}

# Check to see Linux VM is running VSS backup daemon
$sts = RunRemoteScript "STOR_VSS_Check_VSS_Daemon.sh"
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    return $False
}

Write-Output "VSS Daemon is running " >> $summaryLog

# Install the Windows Backup feature
Write-Output "Checking if the Windows Server Backup feature is installed..."
try { Add-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature:$true -Restart:$false }
Catch { Write-Output "Windows Server Backup feature is already installed, no actions required."}

if ($testSecureBootVM)
{
    #
    # Check if Secure boot settings are in place before the backup
    #
    $firmwareSettings = Get-VMFirmware -VMName $vm.Name
    if ($firmwareSettings.SecureBoot -ne "On")
    {
        "Error: Secure boot settings changed"
        return $False
    }
}

# Create a file on the VM before backup
$sts = CreateFile
if (-not $sts[-1])
{
    Write-Output "ERROR: Can not create file"
    return $False
}
Write-Output "File created on VM: $vmname" >> $summaryLog

# Remove Existing Backup Policy
try { Remove-WBPolicy -all -force }
Catch { Write-Output "No existing backup policy to remove"}

# Set up a new Backup Policy
$policy = New-WBPolicy

# Set the backup backup location
$backupLocation = New-WBBackupTarget -VolumePath $driveletter

# Define VSS WBBackup type
Set-WBVssBackupOptions -Policy $policy -VssCopyBackup

# Add the Virtual machines to the list
$VM = Get-WBVirtualMachine | where vmname -like $vmName
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VM
Add-WBBackupTarget -Policy $policy -Target $backupLocation

# Display the Backup policy
Write-Output "Backup policy is: `n$policy"

# Start the backup
Write-Output "Backing to $driveletter"
Start-WBBackup -Policy $policy

# Review the results
$BackupTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes
Write-Output "Backup duration: $BackupTime minutes"
"Backup duration: $BackupTime minutes" >> $summaryLog

$sts=Get-WBJob -Previous 1
if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0)
{
    Write-Output "ERROR: VSS Backup failed"
    Write-Output $sts.ErrorDescription
    $retVal = $false
    return $retVal
}

Write-Output "`nBackup success!`n"
# Let's wait a few Seconds
Start-Sleep -Seconds 70

# Delete file on the VM
$sts = DeleteFile
if (-not $sts[-1])
{
    Write-Output "ERROR: Can not delete file"
    return $False
}
Write-Output "File deleted on VM: $vmname" >> $summaryLog

# Start the Restore
Write-Output "`nNow let's do restore ...`n"

# Get BackupSet
$BackupSet=Get-WBBackupSet -BackupTarget $backupLocation

# Start restore
Start-WBHyperVRecovery -BackupSet $BackupSet -VMInBackup $BackupSet.Application[0].Component[0] -Force -WarningAction SilentlyContinue
$sts=Get-WBJob -Previous 1
if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0)
{
    Write-Output "ERROR: VSS Restore failed"
    Write-Output $sts.ErrorDescription
    $retVal = $false
    return $retVal
}

# Review the results
$RestoreTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes
Write-Output "Restore duration: $RestoreTime minutes"
"Restore duration: $RestoreTime minutes" >> $summaryLog

# Make sure VM exists after VSS backup/restore operation
$vm = Get-VM -Name $vmName -ComputerName $hvServer
    if (-not $vm)
    {
        Write-Output "ERROR: VM ${vmName} does not exist after restore"
        return $False
    }
Write-Output "Restore success!"

# After Backup Restore VM must be off make sure that.
if ( $vm.state -ne "Off" )
{
    Write-Output "ERROR: VM is not in OFF state, current state is " + $vm.state
    return $False
}

# Now Start the VM
$timeout = 300
$sts = Start-VM -Name $vmName -ComputerName $hvServer
if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout ))
{
    Write-Output "ERROR: ${vmName} failed to start"
    return $False
}
else
{
    Write-Output "INFO: Started VM ${vmName}"
}

Start-Sleep -s 60
# Now Check the boot logs in VM to verify if there is no Recovering journals in it .
$sts=CheckRecoveringJ
if ($sts[-1])
{
    Write-Output "ERROR: Recovering Journals in Boot log File, VSS Backup/restore is Failed "
    Write-Output "No Recovering Journal in boot logs: Failed" >> $summaryLog
    return $False
}
else
{
    $sts = CheckFile
    if (-not $sts[-1])
        {
            Write-Output "ERROR: File is not present file"
            Write-Output "File is not present on VM After Backup/Restore: Failed" >> $summaryLog
            return $False
        }

    Write-Output "INFO: File present on VM: $vmName"
    Write-Output "File present on VM After Backup/Restore: Success" >> $summaryLog
    $results = "Passed"
    $retVal = $True
    Write-Output "INFO: VSS Back/Restore: Success"
    Write-Output "Recovering Journal in boot msg: Success" >> $summaryLog

    if ( $testSecureBootVM )
    {
        #
        # Check if Secure boot settings are in place before the backup
        #
        $firmwareSettings = Get-VMFirmware -VMName $vm.Name
        if ($firmwareSettings.SecureBoot -ne "On")
        {
            "Error: Secure boot settings changed" >> $summaryLog
            return $False
        }
    }
}

# Remove Created Backup
Write-Output "Removing old backups from $backupLocation"
try { Remove-WBBackupSet -BackupTarget $backupLocation -Force -WarningAction SilentlyContinue }
Catch { Write-Output "No existing backup's to remove"}

Write-Output "INFO: Test ${results}"
return $retVal
