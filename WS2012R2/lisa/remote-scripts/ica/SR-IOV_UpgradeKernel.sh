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
# This script install the latest kernel on RHEL, SLES or Ubuntu
#
########################################################################

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

if is_fedora ; then
	yum install kernel -y

elif is_ubuntu ; then
	DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

elif is_suse ; then
	zypper --non-interactive dist-upgrade
fi

if [ $? -ne 0 ]; then
	LogMsg "ERROR: Failed to install kernel"
    SetTestStateFailed
    exit 1
else
	LogMsg "Kernel was installed successfully"
	# Convert eol
    dos2unix collect_gcov_data.sh

    # Source utils.sh
    . collect_gcov_data.sh || {
        echo "Error: unable to source collect_gcov_data.sh!"
        echo "TestAborted" > state.txt
        exit 2
    }
	SetTestStateCompleted
fi