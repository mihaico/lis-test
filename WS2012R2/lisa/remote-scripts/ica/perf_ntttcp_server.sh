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

#######################################################################
#
# perf_ntttcp_server.sh
#
# Description:
#     A multiple-thread based Linux network throughput benchmark tool.
#     For the test to run you have to install ntttcp-for-linux from github: https://github.com/Microsoft/ntttcp-for-linux
#
# Requirements:
#   - GCC installed
#
#Example run
#
#To measure the network performance between two multi-core serves running SLES 12, NODE1 (192.168.4.1) and NODE2 (192.168.4.2), connected via a 40 GigE connection.
#
#On NODE1 (the receiver), run: ./ntttcp -r
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_NTTTCPRUNNING="NtttcpRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

LogMsg() {
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

#######################################################################
#
# Main script body
#
#######################################################################
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting running the script"

#
# Delete any old summary.log file
#
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

# Convert eol
dos2unix utils.sh
dos2unix perf_utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source perf_utils.sh
. perf_utils.sh || {
    echo "Error: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

#Apling performance parameters
setup_sysctl
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi

# In case of error
case $? in
    0)
        # do nothing, init succeeded
        ;;
    1)
        LogMsg "Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "Unable to use test state file. Aborting..."
        UpdateSummary "Unable to use test state file. Aborting..."
        # need to wait for test timeout to kick in
        # hailmary try to update teststate
        sleep 60
        echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "Error: unable to source constants file. Aborting..."
        UpdateSummary "Error: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # should not happen
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

#
# Make sure the required test parameters are defined
#

#Get test synthetic interface
declare __iface_ignore

# Parameter provided in constants file
#   ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#   it is not touched during this test (no dhcp or static ip assigned to it)

if [ "${STATIC_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter STATIC_IP2 is not defined in constants file! Make sure you are using the latest LIS code."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
else

    CheckIP "$STATIC_IP2"

    if [ 0 -ne $? ]; then
        msg="Test parameter STATIC_IP2 = $STATIC_IP2 is not a valid IP Address"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 10
    fi

    # Get the interface associated with the given ipv4
    __iface_ignore=$(ip -o addr show | grep "$STATIC_IP2" | cut -d ' ' -f2)
fi

# Retrieve synthetic network interfaces
GetSynthNetInterfaces

if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
    msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 10
fi

LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"

# Test interfaces
declare -i __iterator
for __iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
    ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
    if [ 0 -ne $? ]; then
        msg="Invalid synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 20
    fi
done

LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"

#
# Check for internet protocol version
#
CheckIPV6 "$SERVER_IP"
if [[ $? -eq 0 ]]; then
    ipVersion="-6"
else
    ipVersion=$null
fi

echo "Installing LAGSCOPE ..." >> ~/summary.log
if [ "$(which lagscope)" == "" ]; then
    rm -rf lagscope
    git clone https://github.com/Microsoft/lagscope
    if [ $? -eq 0 ]; then
        cd lagscope/src
        make && make install
        echo "LAGSCOPE installed.." >> ~/summary.log
        LogMsg "LAGSCOPE instaled.."
    fi        
cd $HOME
fi

LogMsg "Enlarging the system limit"
ulimit -n 20480
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to enlarged system limit"
    UpdateTestState $ICA_TESTABORTED
fi

#
# Distro specific setup
#
GetDistro

case "$DISTRO" in
debian*|ubuntu*)
    LogMsg "Installing sar on Ubuntu"
    apt-get install sysstat -y
    if [ $? -ne 0 ]; then
        msg="Error: sysstat failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    apt-get install build-essential git -y
    if [ $? -ne 0 ]; then
        msg="Error: Build essential failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    service ufw status
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Ubuntu"
        service ufw stop
        if [ $? -ne 0 ]; then
                msg="Error: Failed to stop ufw"
                LogMsg "${msg}"
                echo "${msg}" >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 85
        fi
    fi
    ;;
redhat_5|redhat_6|centos_6)
    if [ "$DISTRO" == "redhat_6" ] || ["$DISTRO" == "centos_6" ]; then
        # Import CERN's GPG key
        rpm --import http://ftp.scientificlinux.org/linux/scientific/5x/x86_64/RPM-GPG-KEYs/RPM-GPG-KEY-cern
        if [ $? -ne 0 ]; then
            msg="Error: Failed to import CERN's GPG key."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        # Save repository information
        wget -O /etc/yum.repos.d/slc6-devtoolset.repo http://linuxsoft.cern.ch/cern/devtoolset/slc6-devtoolset.repo
        if [ $? -ne 0 ]; then
            msg="Error: Failed to save repository information."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        # The below will also install all the required dependencies
        yum install -y devtoolset-2-gcc-c++
        if [ $? -ne 0 ]; then
            msg="Error: Failed to install the new version of gcc."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        echo "source /opt/rh/devtoolset-2/enable" >> /root/.bashrc
        source /root/.bashrc
    fi
    LogMsg "Check iptables status on RHEL"
    service iptables status
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat"
        iptables -X
        iptables -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service iptables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        service ip6tables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop ip6tables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig iptables off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
redhat_7)
    LogMsg "Check iptables status on RHEL"
    systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7"
        systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop firewalld"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        systemctl stop firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off firewalld. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi

    LogMsg "Check iptables status on RHEL 7"
    service iptables status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service iptables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig iptables off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
suse_12)
    LogMsg "Check iptables status on SLES 12"
    service SuSEfirewall2 status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service SuSEfirewall2 stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig SuSEfirewall2 off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
esac

git clone https://github.com/Microsoft/ntttcp-for-linux.git

# Get the root directory of the tarball
#
rootDir="ntttcp-for-linux"
LogMsg "rootDir = ${rootDir}"

cd ${rootDir}/src
#
# Build ntttcp
#
rm -f /usr/bin/ntttcp

make
if [ $? -ne 0 ]; then
    msg="Error: Unable to build ntttcp"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi

make install
if [ $? -ne 0 ]; then
    msg="Error: Unable to install ntttcp"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 110
fi

if [ $DISTRO -eq "suse_12" ]; then
    ldconfig
    if [ $? -ne 0 ]; then
        msg="Warning: Couldn't run ldconfig, there might be shared library errors"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
fi

# go back to test root folder
cd ~

# set static ips for test interfaces
declare -i __iterator=0

while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
    LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
    CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $SERVER_IP $NETMASK

    if [ 0 -ne $? ]; then
        msg="Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 120
    fi

    : $((__iterator++))

done

#
# Start ntttcp server instances
#
sleep 3
LogMsg "Ntttcp is ready to start in server mode."

UpdateTestState $ICA_NTTTCPRUNNING
LogMsg "Ntttcp server instances are now ready to run"
