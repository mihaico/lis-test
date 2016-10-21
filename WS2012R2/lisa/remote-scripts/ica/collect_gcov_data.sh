#!/bin/bash
# Function to get dump gcov data for daemon processes
DumpGcovDaemon()
{
    if [ -z "$1" ]
      then
        echo "Error: please specify the daemon process/es name"
        exit
    fi

    echo "set pagination off" > ~/.gdbinit
    for process in "$@"
    do
        pid=`pidof ${process}`
        if [ -z "$pid" ]
        then
            echo "Error: could not find process: $process"
            continue
        fi
        gcov_tmp_file=/root/gcov_tmp_${pid}
        gcov_log_file=/root/gcov_log_${pid}
        echo "call __gcov_flush()" > ${gcov_tmp_file}
        echo "thread apply all call __gcov_flush()" >> ${gcov_tmp_file}
        gdb -p ${pid} -batch -x ${gcov_tmp_file} --args ${process} > ${gcov_log_file} 2>&1
        rm -f ${gcov_tmp_file}
        if [ -f ${gcov_log_file} ]; then
            rm -f ${gcov_log_file}
        fi
    done
    rm -f ~/.gdbinit
}

SOURCE_LOC="/home/test/linux-4.8.3/"
DRIVER_GCOV_LOC="/sys/kernel/debug/gcov/home/test/linux-4.8.3/"
DAEMON_GCOV_LOC="/home/test/linux-4.8.3/tools/hv/"

declare -a daemons=( 'hv_kvp_daemon' 'hv_vss_daemon' 'hv_fcopy_daemon' )
DumpGcovDaemon "${daemons[@]}"
declare -a daemons_loc=( 'tools/hv/hv_kvp_daemon.c'
                         'tools/hv/hv_fcopy_daemon.c'
                         'tools/hv/hv_vss_daemon.c' )
rm -f ~/gcov_data.zip
cd ${DAEMON_GCOV_LOC}
for daemon in "${daemons_loc[@]}"
do
    rm -rf *.gcov
    gcov ${SOURCE_LOC}${daemon} -o ${DAEMON_GCOV_LOC}
    zip ~/gcov_data.zip $(basename "${daemon}").gcov
done

declare -a drivers_loc=( 'drivers/hv/channel.c'
                         # af_hvsock.c - not found on upstream
                         'drivers/hv/channel_mgmt.c'
                         'drivers/hv/connection.c'
                         'drivers/hid/hid-core.c'
                         'drivers/hid/hid-debug.c'
                         'drivers/hid/hid-hyperv.c'
                         'drivers/hid/hid-input.c'
                         'drivers/hid/hv.c'
                         #'drivers/hv/hv_balloon.c' - not instrumented
                         #'drivers/hv/hv_compat.c' - not instrumented
                         'drivers/hv/hv_fcopy.c'
                         'drivers/hv/hv_kvp.c'
                         'drivers/hv/hv_snapshot.c'
                         'drivers/hv/hv_util.c'
                         'drivers/hv/hv_utils_transport.c'
                         # hvnd_addr.c - not found on upstream
                         'drivers/input/serio/hyperv-keyboard.c'
                         'drivers/video/fbdev/hyperv_fb.c'
                         'drivers/net/hyperv/netvsc.c'
                         'drivers/net/hyperv/netvsc_drv.c'
                         # 'drivers/infiniband/hw/cxgb4/provider.c' - not instrumented
                         'drivers/hv/ring_buffer.c'
                         'drivers/net/hyperv/rndis_filter.c'
                         'drivers/scsi/storvsc_drv.c'
                         # vmbus_rdma.c - not found on upstream )
                         'drivers/hv/vmbus_drv.c' )

declare -a lib_files=( 'hyperv.h' 'mshyperv.h' 'sync_bitops.h'
                       'access_ok.h' 'be_byteshift.h' 'be_memmove.h'
                       'be_struct.h' 'generic.h' 'le_byteshift.h' 'le_memmove.h'
                       'le_struct.h' 'memmove.h' 'packed_struct.h'
                       'af_hvsock.h' 'atomic.h' 'export.h' 'hid-debug.h' 'hid.h'
                       'hidraw.h' 'hv_compat.h' 'rndis.h' 'hid-uuid.h'
                       'hid.h' )
cd ${SOURCE_LOC}
for driver in "${drivers_loc[@]}"
do
    rm -rf *.gcov
    gcov ${SOURCE_LOC}${driver} -o ${DRIVER_GCOV_LOC}$(dirname "${driver}")
    zip ~/gcov_data.zip $(basename "${driver}").gcov
    for lib in "${lib_files[@]}"
    do
        if [ -f $(basename "${lib}").gcov ]; then
            zip ~/gcov_data.zip $(basename "${lib}").gcov
        fi
    done
done

#gcovr -g -k -r . --html --html-details -o /tmp/kvp_normal.html
