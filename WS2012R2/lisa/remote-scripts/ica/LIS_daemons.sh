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
# This script is preparing, compiling and installing the LIS daemons and
# the dependencies from the upstream kernel code (tools/hv).
# Linux distribution vendors must adapt this code to the environment
# specific setup.
#
# For SUSE 12 the upstream code is no longer compatible out-of-the-box
# with the system's configuration and file paths.
#
########################################################################

set -e
set -x

ICA_TESTRUNNING="TestRunning"       # The test is running
ICA_TESTCOMPLETED="TestCompleted"   # The test completed successfully
ICA_TESTABORTED="TestAborted"       # Error during setup of test
ICA_TESTFAILED="TestFailed"         # Error during execution of test

CONSTANTS_FILE="constants.sh"
LINUX_VERSION=$(uname -r)

UpdateTestState()
{
    echo $1 > ~/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState $ICA_TESTRUNNING
echo "Updating test case state to running"


if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ -e ~/summary.log ]; then
    echo "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Start the testing
#
UpdateSummary "KernelRelease=${LINUX_VERSION}"
UpdateSummary "$(uname -a)"

LinuxRelease()
{
    DISTRO=$(grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version})

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        Cent??*6*)
            echo "CENTOS6";;
        Cent??*7*)
            echo "CENTOS7";;
        *SUSE*)
            echo "SLES";;
        *Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
        *)
            echo "Error: Distro not supported!";;
    esac
}

prestage_daemons()
{
    cd linux-next/tools/hv/
        if [ $? -ne 0 ]; then
            echo "Error: Hv folder is not present."  >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    mkdir -p /usr/include/uapi/linux/
         if [ $? -ne 0 ]; then
            echo "Error: Unable to create linux folder."
         fi
    cp /root/linux-next/include/linux/hyperv.h /usr/include/linux
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hyper.h to /usr/include/linux." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    cp /root/linux-next/include/uapi/linux/hyperv.h /usr/include/uapi/linux/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hyperv.h to /usr/include/uapi/linux." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    cp /root/linux-next/include/linux/hyperv.h /usr/include/linux
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hyper.h to /usr/include/linux." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi

    cp /root/linux-next/tools/hv/hv_get_dhcp_info.sh /usr/sbin/hv_get_dhcp_info
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv_get_dhcp_info to /usr/sbin." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    cp /root/linux-next/tools/hv/hv_get_dns_info.sh /usr/sbin/hv_get_dns_info
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv_get_dns_info to /usr/sbin." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi

    chmod 755 /usr/sbin/hv_get_*_info
    sed -i 's,#include <linux/hyperv.h>,#include <uapi/linux/hyperv.h>,' hv_kvp_daemon.c
        if [ $? -ne 0 ]; then
            echo "Error: Unable to add hyperv.h in hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    sed -i 's,#include <linux/hyperv.h>,#include <uapi/linux/hyperv.h>,' hv_vss_daemon.c
        if [ $? -ne 0 ]; then
            echo "Error: Unable to add hyperv.h in hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    sed -i 's,#include <linux/hyperv.h>,#include <uapi/linux/hyperv.h>,' hv_fcopy_daemon.c
        if [ $? -ne 0 ]; then
            echo "Error: Unable to add hyperv.h in hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    echo "Info: Compiling LIS daemons." >> ~/summary.log
    make
        if [ $? -ne 0 ]; then
            echo "Error: Unable to compile the LIS daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    sleep 5
return 0
}

ConfigRhel()
{
    kill `ps -ef | grep hyperv | grep -v grep | awk '{print $2}'`
        if [ $? -ne 0 ]; then
  			echo "Error: Unable to kill daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    if [[ $(systemctl list-units --type=service | grep hyperv) ]]; then
        echo "Running daemons are being stopped." >> ~/summary.log
            systemctl stop hypervkvpd.service 
            if [ $? -ne 0 ]; then
                    echo "Error: Unable to stop hypervkvpd." >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
            fi
            systemctl stop hypervvssd.service 
            if [ $? -ne 0 ]; then
                     echo "Error: Unable to stop hypervvssd." >> ~/summary.log
                     UpdateTestState $ICA_TESTFAILED
            fi
            systemctl stop hypervfcopyd.service
             if [ $? -ne 0 ]; then
                    echo "Error: Unable to stop hypervfcopyd." >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
            fi
        echo "Running daemons stopped." >> ~/summary.log
    fi
    echo "Info: Backing up default daemons." >> ~/summary.log

    yes | cp /usr/sbin/hypervkvpd /usr/sbin/hypervkvpd.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp /usr/sbin/hypervvssd /usr/sbin/hypervvssd.old
        if [ $? -ne 0 ]; then
             echo "Error: Unable to copy hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp /usr/sbin/hypervfcopyd /usr/sbin/hypervfcopyd.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    echo "Info: Default daemons backed-up." >> ~/summary.log
    echo "Info: Copying compiled daemons." >> ~/summary.log
    yes | mv hv_kvp_daemon /usr/sbin/hypervkvpd
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | mv hv_vss_daemon /usr/sbin/hypervvssd
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-vss-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | mv hv_fcopy_daemon /usr/sbin/hypervfcopyd
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    echo "Compiled daemons copied." >> ~/summary.log
    sed -i 's,ExecStart=/usr/sbin/hypervkvpd,ExecStart=/usr/sbin/hypervkvpd -n,' /usr/lib/systemd/system/hypervkvpd.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to modify hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    sed -i 's,ExecStart=/usr/sbin/hypervvssd,ExecStart=/usr/sbin/hypervvssd -n,' /usr/lib/systemd/system/hypervvssd.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to modify hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    sed -i 's,ExecStart=/usr/sbin/hypervfcopyd,ExecStart=/usr/sbin/hypervfcopyd -n,' /usr/lib/systemd/system/hypervfcopyd.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to modify hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi

    systemctl daemon-reload
        if [ $? -ne 0 ]; then
            echo "Error: Unable to reload daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    systemctl start hypervkvpd.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    systemctl start hypervvssd.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    systemctl start hypervfcopyd.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi

    echo "Info: LIS daemons started." >> ~/summary.log
    echo "Result : Test Completed Successfully" >> ~/summary.log
    UpdateTestState $ICA_TESTCOMPLETED
}

ConfigSles()
{
    kill `ps -ef | grep hv | grep daemon | awk '{print $2}'`

    echo "Info: Backing up default daemons." >> ~/summary.log
    yes | cp /usr/lib/hyper-v/bin/hv_kvp_daemon /usr/lib/hyper-v/bin/hv_kvp_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to back-up hv_kvp_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp /usr/lib/hyper-v/bin/hv_vss_daemon /usr/lib/hyper-v/bin/hv_vss_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to back-up hv_vss_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp /usr/lib/hyper-v/bin/hv_fcopy_daemon /usr/lib/hyper-v/bin/hv_fcopy_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to back-up hv_fcopy_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    echo "Info: Default daemons backed-up." >> ~/summary.log
    echo "Info: Copying compiled daemons." >> ~/summary.log

    yes | cp hv_kvp_daemon  /usr/lib/hyper-v/bin/hv_kvp_daemon
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy compiled hv_kvp_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp hv_vss_daemon  /usr/lib/hyper-v/bin/hv_vss_daemon
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy compiled hv_vss_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp hv_fcopy_daemon /usr/lib/hyper-v/bin/hv_fcopy_daemon
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy compiled hv_fcopy_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    	echo "Info: Compiled LIS daemons copied." >> ~/summary.log
	
	# Upstream hv tools use /usr/libexec/hypervkvpd/ as the new kvp files path
	mkdir -p /usr/libexec/hypervkvpd/
	cp /root/linux-next/tools/hv/hv_get_dhcp_info.sh /usr/libexec/hypervkvpd//hv_get_dhcp_info
		if [ $? -ne 0 ]; then
			echo "Error: Unable to copy hv_get_dhcp_info to /usr/libexec/hypervkvpd/." >> ~/summary.log
			UpdateTestState $ICA_TESTABORTED
		fi
	cp /root/linux-next/tools/hv/hv_get_dns_info.sh /usr/libexec/hypervkvpd//hv_get_dns_info
		if [ $? -ne 0 ]; then
			echo "Error: Unable to copy hv_get_dns_info to /usr/libexec/hypervkvpd/." >> ~/summary.log
			UpdateTestState $ICA_TESTABORTED
		fi
	cp /root/linux-next/tools/hv/hv_set_ifconfig.sh /usr/libexec/hypervkvpd//hv_set_ifconfig
		if [ $? -ne 0 ]; then
			echo "Error: Unable to copy hv_set_ifconfig to /usr/libexec/hypervkvpd/." >> ~/summary.log
			UpdateTestState $ICA_TESTABORTED
		fi

    chmod 755 /usr/libexec/hypervkvpd/hv*
	
    systemctl daemon-reload
        if [ $? -ne 0 ]; then
            echo "Error: Unable to reload daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    if [ -d /run/hv_kvp_daemon ]; then
        rm -rf /run/hv_kvp_daemon
            if [ $? -eq 0 ]; then
                systemctl start hv_kvp_daemon.service
                    if [ $? -ne 0 ]; then
                        echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
                        UpdateTestState $ICA_TESTFAILED
                    fi
            fi
    fi

    if [ -d /run/hv_vss_daemon ]; then
        rm -rf /run/hv_vss_daemon
            if [ $? -eq 0 ]; then
                systemctl start hv_vss_daemon.service
                    if [ $? -ne 0 ]; then
                        echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
                        UpdateTestState $ICA_TESTFAILED
                    fi
            fi
    fi

    if [ -d /run/hv_fcopy_daemon ]; then
        rm -rf /run/hv_fcopy_daemon
            if [ $? -eq 0 ]; then
                systemctl start hv_fcopy_daemon.service
                    if [ $? -ne 0 ]; then
                        echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
                        UpdateTestState $ICA_TESTFAILED
                    fi
            fi
    fi

    echo "Info: LIS daemons started." >> ~/summary.log
    echo "Result: Test Completed Successfully" >> ~/summary.log
    UpdateTestState $ICA_TESTCOMPLETED
}

ConfigCentos()
{
    kill `ps -ef | grep daemon | grep -v grep | awk '{print $2}'`
        if [ $? -ne 0 ]; then
            echo "Error: Unable to kill daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    if [[ $(service --status -all | grep _daemon) ]]; then
        echo "Running daemons are being stopped." >> ~/summary.log
            service hypervkvpd stop
            if [ $? -ne 0 ]; then
                    echo "Error: Unable to stop hypervkvpd." >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
            fi
            service hypervvssd stop
            if [ $? -ne 0 ]; then
                     echo "Error: Unable to stop hypervvssd." >> ~/summary.log
                     UpdateTestState $ICA_TESTFAILED
            fi
            service hypervfcopyd stop
             if [ $? -ne 0 ]; then
                    echo "Error: Unable to stop hypervfcopyd." >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
            fi
        echo "Info: Running LIS daemons stopped." >> ~/summary.log
    fi
    echo "Info: Backing up default daemons." >> ~/summary.log

    yes | cp /usr/sbin/hv_kvp_daemon /usr/sbin/hv_kvp_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp /usr/sbin/hv_vss_daemon /usr/sbin/hv_vss_daemon.old
        if [ $? -ne 0 ]; then
             echo "Error: Unable to copy hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp /usr/sbin/hv_fcopy_daemon /usr/sbin/hv_fcopy_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    echo "Info: Default daemons backed-up." >> ~/summary.log
    echo "Info: Copying compiled daemons." >> ~/summary.log
    yes | mv hv_kvp_daemon /usr/sbin/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | mv hv_vss_daemon /usr/sbin/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-vss-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | mv hv_fcopy_daemon /usr/sbin/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    echo "Compiled daemons copied." >> ~/summary.log

    service hypervkvpd start
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    service hypervvssd start 
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    service hypervfcopyd start
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi

    echo "Info: LIS daemons started." >> ~/summary.log
    echo "Result: Test Completed successfully" >> ~/summary.log
    UpdateTestState $ICA_TESTCOMPLETED
}

ConfigUbuntu()
{
    echo "Backing up default daemons." >> ~/summary.log
    yes | cp /usr/sbin/hv_kvp_daemon /usr/sbin/hv_kvp_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to back up hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    yes | cp /usr/sbin/hv_vss_daemon /usr/sbin/hv_vss_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to back up hv-vss-daemon." >>~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    yes | cp /usr/sbin/hv_fcopy_daemon /usr/sbin/hv_fcopy_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to back up hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
    echo "Info: Default daemons backed up." >> ~/summary.log
    echo "Info: Copying compiled daemons." >> ~/summary.log

    yes | cp hv_kvp_daemon  /usr/sbin/hv_kvp_daemon
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy compiled hv_kvp_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp hv_vss_daemon  /usr/sbin/hv_vss_daemon
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy compiled hv_vss_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    yes | cp hv_fcopy_daemon /usr/sbin/hv_fcopy_daemon
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy compiled hv_fcopy_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi

    echo "Compiled daemons copied." >> ~/summary.log
    systemctl daemon-reload
        if [ $? -ne 0 ]; then
            echo "Error: Unable to reload daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    systemctl start hv-kvp-daemon.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    systemctl start hv-vss-daemon.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv_vss_daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    systemctl start hv-fcopy-daemon.service
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi

    echo "Info: LIS daemons started." >> ~/summary.log
    echo "Result: Test Completed successfully" >> ~/summary.log
    UpdateTestState $ICA_TESTCOMPLETED
}

if [ -d "/root/net-next" ]; then
	ln -s /root/net-next/ /root/linux-next
fi

prestage_daemons
if [ $? -ne 0 ]; then
	echo "Error: LIS daemons pre-stage steps failed!" >> ~/summary.log
fi

case $(LinuxRelease) in
    "DEBIAN" | "UBUNTU")
        ConfigUbuntu
    ;;

    "CENTOS6")
        ConfigCentos
    ;;

    "RHEL" | "CENTOS7")
        ConfigRhel
    ;;

    "SLES")
        ConfigSles
    ;;

    *)
       echo "Error: Distro '${distro}' is not supported." >> ~/summary.log
       UpdateTestState "TestAborted"
       UpdateSummary "Error: Distro '${distro}' is not supported!"
       exit 1
    ;;
esac
