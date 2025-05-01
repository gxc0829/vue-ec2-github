#!/bin/sh

PATH=/sbin:/bin:/usr/bin
READAHEAD_FILE=/sys/kernel/mm/swap/vma_ra_enabled
PAGE_CLUSTER_FILE=/proc/sys/vm/page-cluster

do_swapoff()
{
        local swap_file=$1
        local readahead
        local page_cluster

        readahead=$(cat $READAHEAD_FILE)
        page_cluster=$(cat $PAGE_CLUSTER_FILE)

        # Enable global readahead with page-cluster=8. This was found to
        # better swapoff performance in AWS instances than the default
        # VMA readhead algorithm with page-cluster=3.
        #
        # page-cluster=8 is a bit of a magical number, take it as just
        # a better default for AWS. It may need to be adjusted per
        # workload through.
        echo false > $READAHEAD_FILE
        echo 8 > $PAGE_CLUSTER_FILE

        swapoff $swap_file

        echo $readahead > $READAHEAD_FILE
        echo $page_cluster > $PAGE_CLUSTER_FILE
}

failed='false'

# Hibernation selects the swapfile with highest priority. Since there may be
# other swapfiles configured, ensure /swap is selected as hibernation
# target by setting to maximum priority.
swap_priority=32767

hibernate()
{
        swapon --priority=$swap_priority /swap && /usr/sbin/pm-hibernate
        if [ $? -ne 0 ]
        then
            logger "Hibernation failed, Sleeping 2 mins before retry"
            failed='true'
        else
            failed='false'
        fi
        do_swapoff /swap
}

case "$2" in
    SBTN)
        # The iteration had been placed here to add retry logic to hibernation 
        # in case of failures and to avoid force stop of instances after 20min
        for i in 1 2 3
        do
          hibernate
          if [ $failed == 'true' ];
          then
            sleep 2m
          else
           break
          fi
       done
       ;;
    *)
        logger "ACPI action undefined: $2" ;;
esac
