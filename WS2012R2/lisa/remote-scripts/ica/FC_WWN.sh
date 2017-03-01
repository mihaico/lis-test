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

########################################################################
#
# FC_WWN.sh
# Description:
#	This script compares the host provided WWNN and WWNP values
#	with the ones detected on a Linux guest VM.
#	To pass test parameters into test cases, the host will create
#	a file named constants.sh. This file contains one or more
#	variable definition.
#
#	The vFC HBA WWN feature is not supported on RedHat 5.x and 6.x
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

UpdateTestState() {
    echo $1 > $HOME/state.txt
}

UpdateSummary() {
	# To add the timestamp to the log file
    echo `date "+%a %b %d %T %Y"` : ${1} >> ~/summary.log
}

cd ~
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

UpdateTestState "TestRunning"

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the constants file!"
    UpdateTestState "TestAborted"
    exit 1
fi

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

# Distro specific detection
GetDistro

case "$DISTRO" in
redhat_5|centos_5|redhat_6|centos_6)
	echo "Info: RedHat/CentOS releases 5.x and 6.x don't support the FC WWN feature! Test will now exit."
	UpdateTestState $ICA_TESTABORTED
	exit 30
    ;;
esac

#
# WWN feature requires the scsi_transport_fc module to be loaded
#
echo "Checking if the scsi_transport_fc module is loaded..."

lsmod | grep -q "scsi_transport_fc"
if [ $? -ne 0 ]; then
	echo "Warning: scsi_transport_fc module is not loaded, trying to load it now..."

	modprobe scsi_transport_fc
	if [ $? -ne 0 ]; then
		echo "Error: Cannot load the scsi_transport_fc module!"
		UpdateTestState $ICA_TESTFAILED
		exit 30
	fi
fi

#
# If vFC SAN connection is present and usable, we should get the below system file
#
if [ -f /sys/class/fc_host ]; then
	echo "Error: The /sys/class/fc_host system file is not present! Test failed!"
	UpdateTestState $ICA_TESTFAILED
	exit 30
fi

#
# Either host1 or host2 special folders must exist, so one of them will be marked as not found, which is expected.
#
if test -n "$(find /sys/class/fc_host/host*/ -maxdepth 1 \( -name 'node_name' -o -name 'port_name' \) -print )"; then
	echo "Info: The WWN node name file and port name file have been found."
else
	echo "Error: The WWN node name file or port name file have not been found!"
	UpdateTestState $ICA_TESTFAILED
	exit 30
fi

#
# Saving the node_name and port_name values from the guest system
#
NODE_NAME_VM=$(cat /sys/class/fc_host/host*/node_name)
PORT_NAME_VM=$(cat /sys/class/fc_host/host*/port_name)

#
# We do a pattern wildcard matching on the values, as the host system doesn't use the 0x notation
#
if ! [[ $NODE_NAME_VM =~ ($expectedWWNN) ]]; then
	echo "Error: Guest VM presented value $NODE_NAME_VM and the host has $expectedWWNN . Test Failed!"
    UpdateTestState $ICA_TESTFAILED
    exit 30
else
    echo "Info: WWNN value is matching with the host. VM presented value is $NODE_NAME_VM"
fi

if ! [[ $PORT_NAME_VM =~ ($expectedWWNP) ]]; then
	echo "Error: Guest VM presented value $PORT_NAME_VM and the host has $expectedWWNP . Test Failed!"
    UpdateTestState $ICA_TESTFAILED
    exit 30
else
    echo "Info: WWNP value is matching with the host. VM presented value is $PORT_NAME_VM"
fi

#
# If we got here, all validations have been successful and no errors have occurred
#
echo "Test Completed Successfully"
UpdateTestState "TestCompleted"
