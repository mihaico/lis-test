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
# vmbus_protocol_version.sh
#
# Description:
#       This script was created to automate the testing of a Linux
#       Integration services. This script will verify that the
#       VMBus protocol string is identified and present in Linux.
#       This is available only for Windows Server 2012 R2 and newer.
#       Windows Server 2012 R2 VMBus protocol version is 2.4, newer
#		Linux kernels have VMBus protocol version 3.0.
#
#       The test performs the following steps:
#    	1. Looks for the VMBus protocol tag inside the dmesg log.
#
#       To pass test parameters into test cases, the host will create
#    	a file named constants.sh. This file contains one or more
#    	variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

#
# Update LISA with the current status
#
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Updating test case state to running"

#
# Source the constants file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    ERRmsg="Error: no ${CONSTANTS_FILE} file"
    LogMsg $ERRmsg
    echo $ERRmsg >> ~/summary.log
fi

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Identifying the test-case ID
#
if [ ! ${TC_COVERED} ]; then
    LogMsg "The TC_COVERED variable is not defined!"
    echo "The TC_COVERED variable is not defined!" >> ~/summary.log
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

#
# Checking for the VMBus protocol string in dmesg
#
vmbus_string=`dmesg | grep "Vmbus version:" | sed 's/^\[[^]]*\] *//'`

if [ "$vmbus_string" = "" ]; then
        LogMsg "Test failed! Could not find the VMBus protocol string in dmesg."
        echo "Test failed! Could not find the VMBus protocol string in dmesg." >> ~/summary.log
        UpdateTestState "TestFailed"
        exit 1
	elif [[ "$vmbus_string" == *hv_vmbus*Hyper-V*Host*Build*Vmbus*version:* ]]; then
		LogMsg "Test passed! Found a matching VMBus string:\n ${vmbus_string}"
		echo -e "Test passed! Found a matching VMBus string:\n${vmbus_string}" >> ~/summary.log
fi

# Convert eol
dos2unix collect_gcov_data.sh

# Source utils.sh
. collect_gcov_data.sh || {
    echo "Error: unable to source collect_gcov_data.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

LogMsg "Test Passed"
UpdateTestState "TestCompleted"
exit 0
