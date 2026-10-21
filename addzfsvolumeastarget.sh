#!/bin/sh
######################
#exit
##########################
cd /pace
echo $@ > /root/addzfsvol
#/pace/addzfsvolumeastarget.sh $pool'/'${vol} $ipaddr $portalport $targetiqn $chapuser $chappas
pool=`echo $@ | awk '{print $1}'`
vol=`echo $@ | awk '{print $2}'`
ipaddr=`echo $@ | awk '{print $3}'`
portalport=`echo $@ | awk '{print $4}'`
target=`echo $@ | awk '{print $5}'`
chapuser=`echo $@ | awk '{print $6}'`
chappas=`echo $@ | awk '{print $7}'`
lunid=`echo $@ | awk '{print $8}'`
# container flavour: no udev, the zvol node and its /dev/zvol link are made here (see czvoldev.sh)
[ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
is_container 2>/dev/null && /pace/czvoldev.sh
disk=`ls -l /dev/zvol/${pool}/$vol | awk -F'/' '{print $NF}'`
echo disk $disk
#chapuser='iqn.1991-05.com.microsoft:desktop-jckvhk3'
#chapuser='MoatazNegm'
#chappass='MezoPass1234'
myhost=`hostname -s`;
change=0
#declare -a iscsitargets=(`cat /pacedata/iscsitargets | awk '{print $2}' `;
#target='iqn.1991-05.com.microsoft:desktop-jckvhk3'
#target='iqn.1994-05.com.redhat:dhcp13038'
#disk='zd0'
ipdom=`echo $ipaddr | sed 's/\.//g'`
diskids=$disk'-'$myhost'-'$vol
iqn='.2016-03.com.'$ipdom':data'
targetcli ls iscsi/ | grep ".$ipdom:data" &>/dev/null
if [ $? -ne 0 ]; then
 targetcli iscsi/ create iqn.2016-03.com.${ipdom}:data &>/dev/null
fi
pdisk=`targetcli ls backstores/block`
# A zvol must not also be exported as a plain node disk (<disk>-<host>, made by caddtargetdisks.sh, which after a
# reboot can run before this script).  Such a stray backstore keeps the device busy, so this volume's own backstore
# could never be created and the target stayed without LUNs.  It holds no data of its own: remove it first.
if echo "$pdisk" | grep -qE "o- ${disk}-${myhost} "; then
 echo "removing stray disk-export backstore ${disk}-${myhost} of zvol $vol"
 targetcli backstores/block delete ${disk}-${myhost}
 pdisk=`targetcli ls backstores/block`
fi
# exact backstore name, not a substring (zd1 also matches zd16, zd0 matches zd0-<host>)
if ! echo "$pdisk" | grep -qE "o- ${diskids} ";
then
 targetcli backstores/block create $diskids /dev/$disk
 echo targetcli backstores/block create $diskids /dev/$disk
fi
#tpg='tpg'$portalport
tpg='tpg1'

#targetcli iscsi/iqn${iqn} create $portalport  
targetcli iscsi/iqn${iqn} set global auto_add_mapped_luns=false
targetcli iscsi/iqn.2016-03.com.$ipdom:data/${tpg}/portals delete 0.0.0.0 3260
targetcli iscsi/iqn${iqn}/${tpg}/luns/ create /backstores/block/$diskids  
targetcli iscsi/iqn${iqn}/${tpg}/acls/ create $target
echo targetcli iscsi/iqn${iqn}/${tpg}/acls/ create $target
cluns=`targetcli iscsi/iqn${iqn}/${tpg}/acls/$target ls`
echo $cluns | grep $diskids 
if [ $? -ne 0 ];
then
 # the number of LUNs already mapped for this initiator (the old 'echo $cluns | wc -l' always counted one line = 1)
 nextlun=`targetcli iscsi/iqn${iqn}/${tpg}/acls/$target ls | grep -c mapped_lun`
 echo targetcli iscsi/iqn${iqn}/${tpg}/acls/$target = $nextlun
 targetcli iscsi/iqn${iqn}/${tpg}/acls/$target create mapped_lun=$nextlun tpg_lun_or_backstore=/backstores/block/$diskids write_protect=0
 echo targetcli iscsi/iqn${iqn}/${tpg}/acls/$target create mapped_lun=$nextlun tpg_lun_or_backstore=/backstores/block/$diskids write_protect=0
fi
targetcli iscsi/iqn${iqn}/${tpg} set attribute demo_mode_write_protect=0 
targetcli iscsi/iqn${iqn}/${tpg} set attribute cache_dynamic_acls=1
# only the initiators listed on the LUN (the acls created above) may log in: generate_node_acls=1 gave every other IQN a dynamic ACL with all LUNs mapped
targetcli iscsi/iqn${iqn}/${tpg} set attribute generate_node_acls=0
targetcli iscsi/iqn${iqn}/${tpg} set attribute authentication=0
targetcli iscsi/iqn${iqn}/${tpg} set auth userid=$chapuser 
targetcli iscsi/iqn${iqn}/${tpg} set auth password=$chappas
targetcli iscsi/iqn.2016-03.com.$ipdom:data/${tpg}/portals create $ipaddr $portalport 
targetcli saveconfig
 #targetcli saveconfig /pacedata/targetconfig
