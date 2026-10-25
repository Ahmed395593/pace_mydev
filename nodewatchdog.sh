#!/bin/bash
# QuickStor node watchdog.  Runs from systemd (quickstor-watchdog.service), independent of the cluster software, because the
# incidents it guards against stop that software: on 2026-10-22 the root file system filled up (5 GB targetcli debug log), the etcd
# container of the node died and nothing started it again, the other node saw it gone and became a second leader.
#   1. keeps the root file system from filling up (targetcli log, journal), repairs a corrupt targetcli prefs file
#   2. starts the etcd container again when it is gone for 1 minute
#   3. exports topstor_users / topstor_groups / topstor_volumes{type} for Prometheus (node_exporter textfile collector), used by the Performance page
LOG=/var/log/quickstor-watchdog.log
CLUSTERIP=10.11.11.250   # the info/summary of the cluster IP feeds the metrics (3.)
log() { echo "$(date '+%F %T') $*" >> $LOG; [ "`stat -c %s $LOG 2>/dev/null`" -gt 5242880 ] && tail -n 2000 $LOG > $LOG.tmp && mv $LOG.tmp $LOG; }
missing=0
while true; do
  # 1. disk space
  use=`df --output=pcent / | tail -1 | tr -dc 0-9`
  tl=/root/.targetcli/log.txt
  if [ -f $tl ] && [ "`stat -c %s $tl`" -gt 209715200 -o "${use:-0}" -ge 85 -a "`stat -c %s $tl`" -gt 20971520 ]; then : > $tl; log "targetcli log truncated (root $use% used)"; fi
  if [ "${use:-0}" -ge 90 ]; then journalctl --vacuum-size=100M >/dev/null 2>&1; log "root file system $use% used: journal vacuumed"; fi
  [ -e /root/.targetcli/prefs.bin ] && [ ! -s /root/.targetcli/prefs.bin ] && rm -f /root/.targetcli/prefs.bin && log "empty targetcli prefs.bin removed"
  # 2. etcd container
  if systemctl is-active --quiet docker && [ `cut -d. -f1 /proc/uptime` -gt 300 ] && [ -z "`docker ps -a --filter name=^etcd$ -q 2>/dev/null`" ] && docker image inspect moataznegm/quickstor:etcd >/dev/null 2>&1; then
    missing=$((missing+1))
  else
    missing=0
  fi
  if [ $missing -ge 3 ]; then
    missing=0
    if docker ps --format '{{.Names}}' | grep -qx flask; then   # the leader publishes its services on the cluster IP
      ip=`docker port flask 5001/tcp | head -1 | cut -d: -f1`; mount="-v /TopStordata/etcd.sh:/runme.sh"
    else
      ip=`nmcli -g ipv4.addresses conn show cmynode | cut -d, -f1 | cut -d/ -f1`; mount=""
    fi
    log "etcd container missing for 1 minute: starting it on $ip"
    docker run -itd --rm --name etcd --hostname etcd -v /etc/localtime:/etc/localtime:ro -v /root/gitrepo/resolv.conf:/etc/resolv.conf -p $ip:2379:2379 -v /TopStor/:/TopStor -v /root/etcddata:/default.etcd $mount --net bridge0 moataznegm/quickstor:etcd >> $LOG 2>&1
  fi
  # 3. inventory metrics for the Performance page (every node writes the same numbers; the page takes max())
  sm=`curl -sk -m 5 https://$CLUSTERIP/api/v1/info/summary 2>/dev/null`
  if [ -n "$sm" ]; then
    mkdir -p /TopStordata/textfile
    echo "$sm" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
o=["# TYPE topstor_users gauge","topstor_users %d" % d["users"],"# TYPE topstor_groups gauge","topstor_groups %d" % d["groups"],"# TYPE topstor_pools gauge","topstor_pools %d" % d["pools"],"# TYPE topstor_volumes gauge"]
o+=["topstor_volumes{type=\"%s\"} %d" % (k,v) for k,v in sorted(d["volumes"].items())]
print("\n".join(o))' > /TopStordata/textfile/topstor.prom.tmp && mv /TopStordata/textfile/topstor.prom.tmp /TopStordata/textfile/topstor.prom
  fi
  # 4. node exporter (Prometheus data of this node for the Performance page): it vanished from a node 2 minutes after a boot, with no
  #    trace of who stopped it; the page then showed one node only.  Start it again whenever it is not running.
  if systemctl is-active --quiet docker && [ `cut -d. -f1 /proc/uptime` -gt 240 ] && ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx promexport \
     && docker image inspect prom/node-exporter >/dev/null 2>&1; then
    nip=`nmcli -g ipv4.addresses conn show cmynode | cut -d, -f1 | cut -d/ -f1`
    log "node exporter not running: starting it on $nip"
    docker rm -f promexport >/dev/null 2>&1
    mkdir -p /TopStordata/textfile
    docker run -d --restart unless-stopped -p $nip:9100:9100 -v /proc:/proc -v /sys:/sys -v /TopStordata/textfile:/textfile:ro --name promexport prom/node-exporter --collector.textfile.directory=/textfile >> $LOG 2>&1
  fi
  # 5. replication ports: an sshd 'Port' line of the partner range 3001-8000 that no partner of this cluster uses any more
  #    (the partner was deleted) is removed and sshd reloaded, so the port can be given to a partner again.
  if [ "`docker exec etcdclient /TopStor/etcdgetlocal.py leader 2>/dev/null | grep -c dhcp`" -ge 1 ]; then
    used=`docker exec etcdclient /TopStor/etcdgetlocal.py Partner --prefix 2>/dev/null | grep -o "/[0-9]*/" | tr -d '/' | sort -u`
    for pt in `grep -o '^Port [0-9]*' /etc/ssh/sshd_config | awk '{print $2}' | sort -u`; do
      [ "$pt" -ge 3001 ] && [ "$pt" -le 8000 ] || continue
      echo "$used" | grep -qx "$pt" && continue
      log "replication port $pt is not used by any partner any more: closing it in sshd"
      cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_port$pt
      sed -i "/^Port $pt\b/d" /etc/ssh/sshd_config
      firewall-cmd -q --permanent --remove-port=$pt/tcp 2>/dev/null; firewall-cmd -q --permanent --remove-port=$pt/udp 2>/dev/null; firewall-cmd -q --reload 2>/dev/null
      sshd -t && systemctl reload sshd
    done
  fi
  sleep 20
done
