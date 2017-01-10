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
    This script will stop networking and attach a CD ISO to the vm. 
    After that it will perform the backup/restore operation. 
    
    It uses a second partition as target. 

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available. 

    A typical xml entry looks like this:

    <test>
    <testName>VSS_BackupRestore_ISO_NoNetwork</testName>
        <testScript>setupscripts\VSS_BackupRestore_ISO_NoNetwork.ps1</testScript> 
        <testParams>
            <param>driveletter=F:</param>
            <param>TC_COVERED=VSS-11</param>
        </testParams>
        <timeout>1200</timeout>
        <OnERROR>Continue</OnERROR>
    </test>
    
    The iOzoneVers param is needed for the download of the correct iOzone version. 

.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_BackupRestore_ISO_NoNetwork.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:'

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

######################################################################
# Runs a remote script on the VM without checking the log 
#######################################################################
function RunRemoteScriptNoState($remoteScript)
{

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh 

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }      

    .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh" 
        return $False
    }
    
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}" 
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f runtest.sh now" 
    if (-not $?)
    {
        Write-Output "Error: Unable to submit runtest.sh to the vm"
        return $False
    }

    del runtest.sh
    return $True
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

$remoteScript = "STOR_VSS_StopNetwork.sh"

# Check input arguments
if ($vmName -eq $null)
{
    Write-Output "ERROR: VM name is null"
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
        "IsoFilename" {$isoFilename = $fields[1].Trim() }
        default  {}          
        }
}

if ($null -eq $sshKey)
{
    Write-Output "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    Write-Output "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    Write-Output "ERROR: Test parameter rootdir was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    Write-Output "ERROR: Test parameter driveletter was not specified."
    return $False
}

if ($null -eq $TestLogDir)
{
    $TestLogDir = $rootdir
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

#
# Make sure the .iso file exists on the HyperV server
#
if (-not ([System.IO.Path]::IsPathRooted($isoFilename)))
{
    $obj = Get-WmiObject -ComputerName $hvServer -Namespace "root\virtualization\v2" -Class "MsVM_VirtualSystemManagementServiceSettingData"
        
    $defaultVhdPath = $obj.DefaultVirtualHardDiskPath
	
    if (-not $defaultVhdPath)
    {
        "Error: Unable to determine VhdDefaultPath on HyperV server ${hvServer}"
        $error[0].Exception
        return $False
    }
   
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }
  
    $isoFilename = $defaultVhdPath + $isoFilename
   
}   

$isoFileInfo = GetRemoteFileInfo $isoFilename $hvServer
if (-not $isoFileInfo)
{
    "Error: The .iso file $isoFilename does not exist on HyperV server ${hvServer}"
    return $False
}


Set-VMDvdDrive -VMName $vmName -ComputerName $hvServer -Path $isoFilename
if (-not $?)
    {
        "Error: Unable to Add ISO $isoFilename" 
        return $False
    }

Write-Output "Attached DVD: Success" >> $summaryLog

# Bring down the network. 
RunRemoteScriptNoState $remoteScript

Start-Sleep -Seconds 3
# echo $x
# return $False

# Make sure network is down.
$sts = ping $ipv4
$pingresult = $False
foreach ($line in $sts)
{
   if (( $line -Like "*unreachable*" ) -or ($line -Like "*timed*")) 
   {
       $pingresult = $True
   }
}

if ($pingresult) 
   {
       Write-Output "Network Down: Success"
       Write-Output "Network Down: Success" >> $summaryLog
   }
   else
   {
       Write-Output "Network Down: Failed" >> $summaryLog
       Write-Output "ERROR: Running $remoteScript script failed on VM!"
       return $False
   }

# Install the Windows Backup feature
Write-Output "Checking if the Windows Server Backup feature is installed..."
try { Add-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature:$true -Restart:$false }
Catch { Write-Output "Windows Server Backup feature is already installed, no actions required."}

# Remove Existing Backup Policy
try { Remove-WBPolicy -all -force }
Catch { Write-Output "No existing backup policy to remove"}

# Set up a new Backup Policy
$policy = New-WBPolicy

# Set the backup backup location
$backupLocation = New-WBBackupTarget -VolumePath $driveletter

# Remove Existing Backups
Write-Output "Removing old backups from $backupLocation"
try { Remove-WBBackupSet -BackupTarget $backupLocation -Force }
Catch { Write-Output "No existing backup's to remove"}

# Define VSS WBBackup type
Set-WBVssBackupOptions -Policy $policy -VssCopyBackup

# Add the Virtual machines to the list
$VMlist = Get-WBVirtualMachine | where vmname -like $vmName
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VMlist
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
Start-Sleep -Seconds 60

# Start the Restore
Write-Output "`nNow let's do restore ...`n"

# Get BackupSet
$BackupSet=Get-WBBackupSet -BackupTarget $backupLocation

# Start Restore
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

# Make sure VM exist after VSS backup/restore operation 
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

# Now Check the boot logs in VM to verify if there is no Recovering journals in it . 
$sts=CheckRecoveringJ
if ($sts[-1])
{
    Write-Output "ERROR: Recovering Journals in Boot log file, VSS backup/restore failed!"
    Write-Output "No Recovering Journal in boot logs: Failed" >> $summaryLog
    return $False
}
else 
{
    $results = "Passed"
    $retVal = $True
    Write-Output "INFO: VSS Back/Restore: Success"   
    Write-Output "Recovering Journal in boot msg: Success" >> $summaryLog
}

# Remove Existing Backups
Write-Output "Removing old backups from $backupLocation"
try { Remove-WBBackupSet -BackupTarget $backupLocation -Force -WarningAction SilentlyContinue }
Catch { Write-Output "No existing backup's to remove"}

Write-Output "INFO: Test ${results}"
return $retVal
