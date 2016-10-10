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

SOURCE_LOC="/home/test/linux-4.8/"
DRIVER_GCOV_LOC="/sys/kernel/debug/gcov/home/test/linux-4.8/"
DAEMON_GCOV_LOC="/home/test/linux-4.8/tools/hv/"

declare -a daemons=( 'hv_kvp_daemon' 'hv_vss_daemon' 'hv_fcopy_daemon' )
DumpGcovDaemon "${daemons[@]}"
declare -a daemons_loc=( 'tools/hv/hv_kvp_daemon.c'
                         'tools/hv/hv_fcopy_daemon.c'
                         'tools/hv/hv_vss_daemon.c' )
rm -f ~/gcov_data.zip
cd ${SOURCE_LOC}
for daemon in "${daemons_loc[@]}"
do
   gcov ${SOURCE_LOC}${daemon} -o ${DAEMON_GCOV_LOC}
   zip ~/gcov_data.zip $(basename "${daemon}").gcov
done

declare -a drivers_loc=( 'drivers/scsi/storvsc_drv.c'
                         'drivers/net/hyperv/netvsc_drv.c'
                         'drivers/hv/vmbus_drv.c'
                         'drivers/hv/hv_util.c' )
for driver in "${drivers_loc[@]}"
do
   gcov ${SOURCE_LOC}${driver} -o ${DRIVER_GCOV_LOC}$(dirname "${driver}")
   zip ~/gcov_data.zip $(basename "${driver}").gcov
done

#gcovr -g -k -r . --html --html-details -o /tmp/kvp_normal.html
