#!/bin/bash

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

# Description:
#   Unload/load modules using modprobe, verify SR-IOV Failover is working
#
#   Steps:
#   1. Verify/install pciutils package
#   2. Using the lspci command, examine the NIC with SR-IOV support
#   3. Run bondvf.sh
#   4. Check network capability
#   5. Unload module(s) (ixgbevf for Intel or mlx4_core and mlx_en for Mellanox)
#   6. Check network capability
#   7. Load module(s) (ixgbevf for Intel or mlx4_core and mlx_en for Mellanox)
#   8. Check network capability
#
#############################################################################################################

# Convert eol
dos2unix SR-IOV_Utils.sh

# Source SR-IOV_Utils.sh. This is the script that contains all the 
# SR-IOV basic functions (checking drivers, making de bonds, assigning IPs)
. SR-IOV_Utils.sh || {
    echo "ERROR: unable to source SR-IOV_Utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Check the parameters in constants.sh
Check_SRIOV_Parameters
if [ $? -ne 0 ]; then
    msg="ERROR: The necessary parameters are not present in constants.sh. Please check the xml test file"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Check if the SR-IOV driver is in use
VerifyVF
if [ $? -ne 0 ]; then
    msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi
UpdateSummary "VF is present on VM!"

# Run the bonding script. Make sure you have this already on the system
# Note: The location of the bonding script may change in the future
RunBondingScript
bondCount=$?
if [ $bondCount -eq 99 ]; then
    msg="ERROR: Running the bonding script failed. Please double check if it is present on the system"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi
LogMsg "BondCount returned by SR-IOV_Utils: $bondCount"

# Set static IP to the bond
ConfigureBond
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the bond!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Create an 1gb file to be sent from VM1 to VM2
Create1Gfile
if [ $? -ne 0 ]; then
    msg="ERROR: Could not create the 1gb file on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Ping Dependency VM
ping -I bond0 -c 10 "$BOND_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    msg="Successfully pinged $BOND_IP2 through bond0 with before unloading the VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
else
    msg="ERROR: Unable to ping $BOND_IP2 through bond0 with VF up. Further testing will be stopped"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Extract VF name that is bonded
interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|bond*\|lo')

# Shut down interface
LogMsg "Unloading the module(s)"
lsmod | grep ixgbevf
if [ $? -eq 0 ]; then
    modprobe -r ixgbevf
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to unload ixgbevf"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
    moduleName='ixgbevf'
fi

lsmod | grep mlx4_en
if [ $? -eq 0 ]; then
    modprobe -r mlx4_en
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to unload mlx_en"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
fi

lsmod | grep mlx4_core
if [ $? -eq 0 ]; then
    modprobe -r mlx4_core
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to unload mlx4_core"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
    moduleName='mlx4'
fi

# Ping the remote host after bringing down the VF
ping -I "bond0" -c 10 "$BOND_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    msg="Successfully pinged $BOND_IP2 through bond0 after unloading VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
else
    msg="ERROR: Unable to ping $BOND_IP2 through bond0 after unloading VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Get TX value before sending the file
txValueBefore=$(ifconfig bond0 | grep "TX packets" | sed 's/:/ /' | awk '{print $3}') 
LogMsg "TX value before sending file: $txValueBefore"

# Send the file
scp -i "$HOME"/.ssh/"$sshKey" -o BindAddress=$BOND_IP1 -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$BOND_IP2":/tmp/"$output_file"
if [ 0 -ne $? ]; then
    msg="ERROR: Unable to send the file from VM1 to VM2 using bond0"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
else
    msg="Successfully sent $output_file to $BOND_IP2"
    LogMsg "$msg"
fi

# Get TX value after sending the file
txValueAfter=$(ifconfig bond0 | grep "TX packets" | sed 's/:/ /' | awk '{print $3}') 
LogMsg "TX value after sending the file: $txValueAfter"

# Compare the values to see if TX increased as expected
txValueBefore=$(($txValueBefore + 50))      

if [ $txValueAfter -lt $txValueBefore ]; then
    msg="ERROR: TX packets insufficient"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi            

msg="Successfully sent file from VM1 to VM2 through bond0 after unloading VF modules"
LogMsg "$msg"
UpdateSummary "$msg"

# Load modules again
LogMsg "Loading the module(s)"
if [ $moduleName == 'ixgbevf' ]; then
    modprobe ixgbevf
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to load ixgbevf"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
elif [ $moduleName == 'mlx4' ]; then
    modprobe mlx4_core
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to load mlx4_core"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi

    modprobe mlx4_en
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to load mlx_en"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi     
fi

# Verify if VF is up
sleep 5
interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|bond*\|lo')
ifconfig $interface
if [ 0 -ne $? ]; then
    msg="ERROR: VF has not restarted from ifconfig after the module was loaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Convert eol
dos2unix collect_gcov_data.sh

# Source utils.sh
. collect_gcov_data.sh || {
    echo "Error: unable to source collect_gcov_data.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Ping the remote host after bringing down the VF
ping -I "bond0" -c 10 "$BOND_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    msg="Successfully pinged $BOND_IP2 through bond0 after VF module was loaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateCompleted
else
    msg="ERROR: Unable to ping $BOND_IP2 through bond0 after VF module was loaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi