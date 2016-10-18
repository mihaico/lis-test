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

param([string] $vmName, [string] $hvServer, [string] $testParams)

function CheckResults(){
    #
    # Checking test results
    #
    $stateFile = "state.txt"

    bin\pscp -q -i ssh\${1} root@${2}:${stateFile} .
    $sts = $?

    if ($sts) {
        if (test-path $stateFile){
            $contents = Get-Content $stateFile
            if ($null -ne $contents){
                if ($contents.Contains('TestCompleted') -eq $True) {                    
                    Write-Output "Info: Test ended successfully"
                    $retVal = $True
                }
                if ($contents.Contains('TestAborted') -eq $True) {
                    Write-Output "Info: State file contains TestAborted failed"
                    $retVal = $False                           
                }
                if ($contents.Contains('TestFailed') -eq $True) {
                    Write-Output "Info: State file contains TestFailed failed"
                    $retVal = $False                           
                }
            }    
            else {
                Write-Output "ERROR: state file is empty!"
                $retVal = $False    
            }
        }
    }
    return $retval
}

Set-PSDebug -Strict

# function which creates an /etc/sysconfig/network-scripts/ifcfg-ethX file for interface ethX
function CreateInterfaceConfig([String]$conIpv4,[String]$sshKey,[String]$MacAddr,[String]$staticIP,[String]$netmask)
{

    # Add delimiter if needed
    if (-not $MacAddr.Contains(":"))
    {
        for ($i=2; $i -lt 16; $i=$i+2)
        {
            $MacAddr = $MacAddr.Insert($i,':')
            $i++
        }
    }

    # create command to be sent to VM. This determines the interface based on the MAC Address.

    $cmdToVM = @"
#!/bin/bash
        cd /root
        if [ -f utils.sh ]; then
            sed -i 's/\r//' utils.sh
            . utils.sh
        else
            exit 1
        fi
        # make sure we have synthetic network adapters present
        GetSynthNetInterfaces
        if [ 0 -ne `$? ]; then
            exit 2
        fi
        # get the interface with the given MAC address
        __sys_interface=`$(grep -il ${MacAddr} /sys/class/net/*/address)
        if [ 0 -ne `$? ]; then
            exit 3
        fi
        __sys_interface=`$(basename "`$(dirname "`$__sys_interface")")
        if [ -z "`$__sys_interface" ]; then
            exit 4
        fi
        echo CreateIfupConfigFile: interface `$__sys_interface >> /root/summary.log 2>&1
        CreateIfupConfigFile `$__sys_interface static $staticIP $netmask >> /root/summary.log 2>&1
        __retVal=`$?
        echo CreateIfupConfigFile: returned `$__retVal >> /root/summary.log 2>&1
        exit `$__retVal
"@

    $filename = "CreateInterfaceConfig.sh"

    # check for file
    if (Test-Path ".\${filename}")
    {
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # delete file unless the Leave_trail param was set to yes.
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
    {
        Remove-Item ".\${filename}"
    }

    # check the return Value of SendFileToVM
    if (-not $retVal)
    {
        return $false
    }

    # execute sent file
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
}

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# IP Address of second VM
$ipv4VM2 = $null

# Name of second VM
$vm2Name = $null

# name of the switch to which to connect
$netAdapterName = $null

# VM1 IPv4 Address
$vm1StaticIP = $null

# VM2 IPv4 Address
$vm2StaticIP = $null

# Netmask used by both VMs
$netmask = $null

#Snapshot name
$snapshotParam = $null

# Mac address for vm1
$vm1MacAddress = $null

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir)
{
    Set-Location -Path $rootDir
    if (-not $?)
    {
        "Error: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "Error: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
    "Error: Could not find setupScripts\NET_Utils.ps1"
    return $false
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "VM2NAME" { $vm2Name = $fields[1].Trim() }
    "sshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    "STATIC_IP1" { $vm1StaticIP = $fields[1].Trim() }
    "STATIC_IP2" { $vm2StaticIP = $fields[1].Trim() }
    "NETMASK" { $netmask = $fields[1].Trim() }
    "SnapshotName" { $SnapshotName = $fields[1].Trim() }
    "TestLogDir" {$logdir = $fields[1].Trim()}
    "NIC"
    {
        $nicArgs = $fields[1].Split(',')
        if ($nicArgs.Length -lt 4)
        {
            "Error: Incorrect number of arguments for NIC test parameter: $p"
            return $false

        }

        $nicType = $nicArgs[0].Trim()
        $networkType = $nicArgs[1].Trim()
        $networkName = $nicArgs[2].Trim()
        $vm1MacAddress = $nicArgs[3].Trim()

        #
        # Validate the network adapter type
        #
        if ("NetworkAdapter" -notcontains $nicType)
        {
            "Error: Invalid NIC type: $nicType . Must be 'NetworkAdapter'"
            return $false
        }

        #
        # Validate the Network type
        #
        if (@("External", "Internal", "Private") -notcontains $networkType)
        {
            "Error: Invalid netowrk type: $networkType .  Network type must be either: External, Internal, Private"
            return $false
        }
    }
    default   {}  # unknown param - just ignore it
    }
}

if (-not $vm1MacAddress)
{
    "Error: test parameter vm1MacAddress was not specified"
    return $False
}

if (-not $vm2Name)
{
    "Error: test parameter vm2Name was not specified"
    return $False
}

# make sure vm2 is not the same as vm1
if ("$vm2Name" -like "$vmName")
{
    "Error: vm2 must be different from the test VM."
    return $false
}

if (-not $sshKey)
{
    "Error: test parameter sshKey was not specified"
    return $False
}

if (-not $ipv4)
{
    "Error: test parameter ipv4 was not specified"
    return $False
}

#set the parameter for the snapshot
$snapshotParam = "SnapshotName = ${SnapshotName}"

#revert VM2
.\setupScripts\RevertSnapshot.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $snapshotParam
Start-sleep -s 5

#
# Verify the VMs exists
#
$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    return $False
}

# hold testParam data for NET_ADD_NIC_MAC script
$vm2testParam = $null
$vm2MacAddress = $null

# Check for a NIC of the given network type on VM2

for ($i = 0 ; $i -lt 3; $i++)
{
   $vm2MacAddress = getRandUnusedMAC $hvServer
   if ($vm2MacAddress)
   {
        break
   }
}
$retVal = isValidMAC $vm2MacAddress
if (-not $retVal)
{
    "Could not find a valid MAC for $vm2Name. Received $vm2MacAddress"
    return $false
}

#construct NET_ADD_NIC_MAC Parameter
$vm2testParam = "NIC=NetworkAdapter,$networkType,$networkName,$vm2MacAddress"

if ( Test-Path ".\setupscripts\NET_ADD_NIC_MAC.ps1")
{
    # Make sure VM2 is shutdown
    if (Get-VM -Name $vm2Name |  Where { $_.State -like "Running" })
    {
        Stop-VM $vm2Name -force

        if (-not $?)
        {
            "Error: Unable to shut $vm2Name down (in order to add a new network Adapter)"
            return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vm2Name |  Where { $_.State -notlike "Off" })
        {
            if ($timeout -le 0)
            {
                "Error: Unable to shutdown $vm2Name"
                return $false
            }

            start-sleep -s 5
            $timeout = $timeout - 5
        }

    }

    .\setupscripts\NET_ADD_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
}
else
{
    "Error: Could not find setupScripts\NET_ADD_NIC_MAC.ps1 ."
    return $false
}

if (-Not $?)
{
    "Error: Cannot add new NIC to $vm2Name"
    return $false
}

# get the newly added NIC
$vm2nic = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $hvServer -IsLegacy:$false | where { $_.MacAddress -like "$vm2MacAddress" }

if (-not $vm2nic)
{
    "Error: Could not retrieve the newly added NIC to VM2"
    return $false
}

# Delete old summary logs
$retVal= SendCommandToVM $ipv4 $sshKey "rm summary.log"

$retVal = CreateInterfaceConfig $ipv4 $sshKey $vm1MacAddress $vm1StaticIP $netmask
if (-not $retVal)
{
    "Failed to create Interface-File on vm $ipv4 for interface with mac $vm1MacAddress, by setting a static IP of $vm1StaticIP netmask $netmask"
    return $false
}


#
# LIS Started VM1, so start VM2
#

if (Get-VM -Name $vm2Name |  Where { $_.State -notlike "Running" })
{
    Start-VM -Name $vm2Name -ComputerName $hvServer
    if (-not $?)
    {
        "Error: Unable to start VM ${vm2Name}"
        $error[0].Exception
        return $False
    }
}


$timeout = 200 # seconds
if (-not (WaitForVMToStartKVP $vm2Name $hvServer $timeout))
{
    "Warning: $vm2Name never started KVP"
}

# get vm2 ipv4
$vm2ipv4 = GetIPv4 $vm2Name $hvServer

# Delete old summary logs
$retVal= SendCommandToVM $vm2ipv4 $sshKey "rm summary.log"

#
# Send utils.sh to second vm.
#
$retVal = SendFileToVM $vm2ipv4 $sshKey ".\remote-scripts\ica\utils.sh" "/root/utils.sh"

# send ifcfg file to each VM

$retVal = CreateInterfaceConfig $vm2ipv4 $sshKey $vm2MacAddress $vm2StaticIP $netmask
if (-not $retVal)
{
    "Failed to create Interface-File on vm $vm2ipv4 for interface with mac $vm2MacAddress, by setting a static IP of $vm2StaticIP netmask $netmask"
    return $false
}

#
# Wait for second VM to set up the test interface
#
Start-Sleep -S 10
$retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\NET_Configure_Vxlan.sh" "/root/NET_Configure_Vxlan.sh"

# check the return Value of SendFileToVM
if (-not $retVal)
{
    return $false
}

$vm="local"
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix NET_Configure_Vxlan.sh && chmod u+x NET_Configure_Vxlan.sh && ./NET_Configure_Vxlan.sh $vm1StaticIP $vm"

$first_result = CheckResults $sshKey $ipv4
if (-not $first_result)
{
    "Error: Configuration problems have occured. Test failed."
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
    return $false
}

Start-Sleep -S 10
$retVal = SendFileToVM $vm2ipv4 $sshKey ".\remote-scripts\ica\NET_Configure_Vxlan.sh" "/root/NET_Configure_Vxlan.sh"

# check the return Value of SendFileToVM
if (-not $retVal)
{
    return $false
}

$vm="remote"
$retVal = SendCommandToVM $vm2ipv4 $sshKey "cd /root && dos2unix NET_Configure_Vxlan.sh && chmod u+x NET_Configure_Vxlan.sh && ./NET_Configure_Vxlan.sh $vm2StaticIP $vm"

#
# Wait to second vm to configure the vxlan interface
#
Start-Sleep -S 10

# create command to be sent to first VM. This verify if we can ping the second vm through test interface and sends the rsync command.

$cmdToVM = @"
#!/bin/bash

    ping -I vxlan0 242.0.0.11 -c 3
    if [ `$? -ne 0 ]; then
        echo "Failed to ping the second vm through vxlan0 after configurations." >> summary.log
        echo "TestAborted" >> state.txt
    else
        echo "Successfuly pinged the second vm through vxlan0 after configurations, connection is good." >> summary.log
        echo "Starting to transfer files with rsync" >> summary.log
        echo "rsync -e 'ssh -o StrictHostKeyChecking=no -i /root/.ssh/rhel5_id_rsa' -avz /root/test root@242.0.0.11:/root" | at now +1 minutes
    fi    

"@

$filename = "vxlan_test.sh"

# check for file
if (Test-Path ".\${filename}")
{
    Remove-Item ".\${filename}"
}

Add-Content $filename "$cmdToVM"

# send file
$retVal = SendFileToVM $ipv4 $sshKey $filename "/root/${$filename}"
# check the return Value of SendFileToVM
if (-not $retVal)
{
    return $false
}

# execute command
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

# extracting the log files
bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
Rename-Item $logdir\summary.log first_vm_summary.log

# Checking results to see if we can go further
$check = CheckResults $sshKey $vm2ipv4
if (-not $check)
{
    "Results are not as expected in configuration. Test failed. Check logs for more details."
    return $false
}

Start-Sleep -S 450
$timeout=200
do {
    sleep 5
    $timeout -= 5
    if ($temporar -eq 0)
    {
        Write-Output "Error: Connection lost to the first VM. Test Failed."
        Stop-VM -Name $vmName -ComputerName $hvServer -Force
        Stop-VM -Name $vm2Name -ComputerName $hvServer -Force
        return $False   
    }
} until(Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )

# If we are here then we still have a connection to VM.
# create command to be sent second VM. Verify if we can ping the first VM and if the test directory was transfered.

$cmdToVM = @"
#!/bin/bash
    ping -I vxlan0 242.0.0.12 -c 3
    if [ `$? -ne 0 ]; then
        echo "Could not ping the first VM through the vxlan interface. Lost connectivity between instances after rsync." >> summary.log 
        echo "TestFailed" >> state.txt
        exit 1
    else
        echo "Ping to first vm succeded, that means the connection is good. Checking if the directory was transfered corectly." >> summary.log
        if [ -d "/root/test" ]; then
            echo "Test directory was found." >> summary.log
            size=``du -h /root/test | awk '{print `$1;}'``
            if [ `$size == "10G" ] || [ `$size == "11G" ]; then
                echo "Test directory has the proper size. Test ended successfuly." >> summary.log
                echo "TestCompleted" >> state.txt
            else
                echo "Test directory doesn't have the proper size. Test failed." >> summary.log
                echo "TestFailed" >> state.txt
                exit 2
            fi
        else
            echo "Test directory was not found." >> summary.log
            echo "TestFailed" >> state.txt
            exit 3
        fi    
    fi
"@

$filename = "results_vxlan.sh"

# check for file
if (Test-Path ".\${filename}")
{
    Remove-Item ".\${filename}"
}

Add-Content $filename "$cmdToVM"

# send file
$retVal = SendFileToVM $vm2ipv4 $sshKey $filename "/root/${$filename}"
# check the return Value of SendFileToVM
if (-not $retVal)
{
    return $false
}

# execute command
$retVal = SendCommandToVM $vm2ipv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename} $STATIC_IP"

# Collect gcov
RunRemoteScript "collect_gcov_data.sh"

$remoteFile = "gcov_data.zip"
$localFile = "${TestLogDir}\${vmName}_${TestName}_storvsc.zip"
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



bin\pscp -q -i ssh\${sshKey} root@${vm2ipv4}:summary.log $logdir

$second_result = CheckResults $sshKey $vm2ipv4
Stop-VM -Name $vm2Name -ComputerName $hvServer -Force
if (-not $second_result)
{
    "Results are not as expected. Test failed."
    return $false
}

return $second_result
