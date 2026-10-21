#!/bin/bash

# Usage: retryvolumedelete.sh <leaderip> <myhost>

leaderip=`echo $@ | awk '{print $1}'`
myhost=`echo $@ | awk '{print $2}'`

MAX_RETRIES=3
RETRY_DELAY=5
LOG_PREFIX="VOLDELRETRY"

log_message() {
    local info=$1
    local msgcode=$2
    local oper1=$3
    local oper2=$4
    docker exec etcdclient /TopStor/logmsg.py $msgcode $info system $oper1 $oper2
}

find_stop_blocking_containers() {
    local volume_path="$pDG/$volname"
    log_message info contpst01 $service_type $volume_path
    container_list=$(docker ps --format "{{.Names}}" | grep -i "$service_type")

    if [ -z "$container_list" ]; then
        log_message info contpin01 $volume_path  $service_type
        return 1
    fi

    while IFS= read -r cname; do
        if docker inspect "$cname" 2>/dev/null | grep -q "$volname"; then
            #`log_message "info" "Stopping blocking container: $cname"
	    log_message info contpst04 "$cname" "$volume_path"
            log_message info contpst02 $cname $volume_path
            if docker stop "$cname" >/dev/null 2>&1; then
                log_message info contpsu02 $cname $volume_path
                return 0
            else
                log_message error contpfa02 $cname $volume_path
                return 1
            fi
        fi
    done <<< "$container_list"

    log_message info contpin02 $volume_path  $service_type
    return 1
}

attempt_volume_deletion() {
    local volume_path="$pDG/$volname"
    log_message info contpst03 $volume_path  .
    /sbin/zfs unmount -f "$volume_path" 2>/dev/null
    /sbin/zfs destroy -rf "$volume_path" 2>/dev/null
    return $?
}


entry=$(/pace/etcdget.py $leaderip cVolToDelete/$myhost)

if [[ "$entry" == "_1" || -z "$entry" ]]; then
    exit 0
fi

IFS="|" read -r pDG volname userreq caller_script <<< "$entry"

if [[ -z "$pDG" || -z "$volname" ]]; then
    echo leader=$leaderip $myhost
    echo entry=$entry
    log_message error contper03 $entry  .
    log_message error contper03 $leaderip $myhost 
    exit 1
fi

log_message info contpin03 $pDG/$volname $userreq 

# Determine service type from caller_script
service_type=""
case "$caller_script" in
    *CIFS*) service_type="CIFS" ;;
    *NFS*) service_type="NFS" ;;
    *ISCSI*) service_type="ISCSI" ;;
    *HOME*) service_type="HOME" ;;
esac


retry_count=0

while [ $retry_count -lt $MAX_RETRIES ]; do

    # Check if etcd key still exists
    entry=$(/pace/etcdget.py "$leaderip" "cVolToDelete/$myhost")
    if [[ "$entry" == "_1" ]]; then
	log_message info contpin04 $pDG/$volname $myhost 
        exit 0
    fi

    find_stop_blocking_containers

    if attempt_volume_deletion; then
	log_message info contpsu01 $pDG/$volname . 
        /pace/etcddel.py "$leaderip" "cVolToDelete/$myhost"
        exit 0
    else
        log_message warning contpwa01 $pDG/$volname $retry_count 
    fi

    retry_count=$((retry_count + 1))
    sleep $RETRY_DELAY
done

log_message error contpfa01 $pDG/$volname $MAX_RETRIES 
exit 1

