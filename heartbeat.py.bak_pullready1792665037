#!/usr/bin/python3

import sys, os, subprocess
from etcdget import etcdget as get
from etcdput import etcdput as put 
from etcddel import etcddel as dels 
from time import sleep
from time import time as stamp

leader, leaderip, myhost, myhostip, nextleader, nextleaderip = '','','','','',''
etcd = ''
dev = 'enp0s8'
os.environ['ETCDCTL_API']= '3'


# QCFIX2: a plain TCP connect says whether etcd answers; nmap against the node's own cluster ip goes through the
# router's proxy ARP and reports the port 'filtered' (so the take-over clean-up waited its full 300 s)
def portopen(ip, port=2379, timeout=2):
    import socket
    try:
        socket.create_connection((ip, int(port)), timeout).close()
        return True
    except Exception:
        return False


def dosync(*args):
  global etcd, leader ,leaderip, myhost, myhostip, nextleader, nextleaderip
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return 




def splitnext(value):
 # nextlead/er is '<host>/<ip>', written by the leader (see leadernextlead).  Older branches wrote the bare
 # host name; a value without a host in it ('None', '_1', '-1') means there is no next leader.
 value = str(value)
 if 'dhcp' not in value:
  return '', ''
 parts = value.split('/')
 return parts[0], (parts[1] if len(parts) > 1 else '')

def getnextlead():
 # read only: a node never announces itself, the leader names the next leader and syncs it to every node
 global etcd, leader ,leaderip, myhost, myhostip, nextleader, nextleaderip
 nextleader, nextleaderip = splitnext(get(etcd,'nextlead/er')[0])
 if nextleader and not nextleaderip:
  nextleaderip = str(get(etcd,'ready/'+nextleader)[0])
 return nextleader , nextleaderip

readyseen = None

def leadernextlead(knowns):
 # LEADER ONLY.  The leader names the next leader: a node that has just become ready, or -- when the
 # current one is not a ready node any more (lost, evacuated, this node itself after a take over, None) --
 # another ready node.  It writes nextlead/er = '<host>/<ip>' and posts the sync request (the request and
 # the leader's own done mark), so the checksyncs looper of every node copies it into its local etcd.
 global etcd, leader ,leaderip, myhost, myhostip, readyseen
 others = [ (k[0].split('/')[1], str(k[1])) for k in knowns if 'ready/' in str(k[0]) and k[0].split('/')[1] != myhost ]
 names = [ o[0] for o in others ]
 new = [] if readyseen is None else [ o for o in others if o[0] not in readyseen ]
 readyseen = set(names)
 if len(others) == 0:
  return
 current = str(get(leaderip,'nextlead/er')[0])
 curhost, curip = splitnext(current)
 if len(new) > 0:
  choice = new[-1]
 elif curhost not in names:
  choice = others[-1]
 else:
  choice = [ o for o in others if o[0] == curhost ][0]
 value = choice[0]+'/'+choice[1]
 if current == value:
  return
 print('next leader is now', value, 'it was', current)
 put(leaderip, 'nextlead/er', value)
 dels(leaderip,'sync/nextlead/Add_er','--prefix')
 dosync('sync/nextlead/Add_er_'+choice[0]+'::'+choice[1]+'/request','nextlead_'+str(stamp()))

def hostlost(host, hostip):
                global etcd, leader ,leaderip, myhost, myhostip, nextleader, nextleaderip
                with open('/root/heartproblem','a') as f:
                        f.write('nmap:\n'+host+' '+hostip)

                stampit = str(stamp())
                port = myport = '2379'
                # from this node's own etcd: asking the lost leader's etcd only waited 2 s for the timeout and returned nothing
                clusterip = get(etcd,'namespace/mgmtip')[0]
                if host == leader:
                    dels(myhostip, 'pools',host)
                    dels(myhostip, 'vol',host)
                    print('leader lost. nextleader is ',nextleader, 'while my host',myhost)
                    nextleader, nextleaderip =  splitnext(get(etcd,'nextlead/er')[0])
                    if nextleader:
                        if not nextleaderip:
                            nextleaderip = myhostip if nextleader == myhost else str(get(etcd,'ready/'+nextleader)[0])
                        leader = nextleader 
                        put(myhostip,'leader',leader)
                    if myhost == nextleader:
                        cmdline='/pace/leaderlost.sh '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+nextleader+' '+nextleaderip+' '+clusterip+' '+host
                        result=subprocess.check_output(cmdline.split(),stderr=subprocess.STDOUT).decode('utf-8')
                        etcd = leaderip
                        dels(leaderip, 'sync/hostdown/'+host,'--prefix')
                        put(leaderip,'sync/hostdown/'+host+'_/request','hostdown_'+stampit)
                        put(leaderip,'sync/hostdown/'+host+'_/request/'+myhost,'hostdown_'+stampit)
                    put(etcd,'refreshdisown/'+myhost,'yes')
                    result='failed'
                    # wait for the cluster ip to answer again, but never for ever: after 5 minutes give up
                    # and go back to the main loop (it used to spin here, without a pause, until a restart)
                    waituntil = stamp() + 300
                    while 'ok' not in str(result):
                        if stamp() > waituntil:
                            print('no leader answers on', leaderip, 'after 5 minutes .... back to the main loop')
                            with open('/root/heartproblem','a') as f:
                                f.write('\nno new leader on '+leaderip+' after 300s\n')
                            break
                        sleep(1)
                        print('chceking new leader')
                        cmdline='nmap --max-rtt-timeout 500ms -n -p '+port+' '+leaderip 
                        result=subprocess.check_output(cmdline.split(),stderr=subprocess.STDOUT).decode('utf-8')
                        if portopen(leaderip, port):
                            result = (host,'ok')
                        else:
                            result = (host,'lost')
                
                else:
                    dels(leaderip, 'pools',host)
                dels(etcd, 'cpuperf/'+host)
                cmdline='/pace/hostlost.sh '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+host
                result=subprocess.check_output(cmdline.split(),stderr=subprocess.STDOUT).decode('utf-8')
                dels(etcd,'ready/',host)
                dels(etcd, 'running/', host)
                dels(etcd, 'host', host)
                dels(etcd, 'known/',host)
                dels(etcd, 'vol',host)
                dels(etcd, 'sync/hostdown',host)

# QCFIX: re-register this node on the leader when its ready/<host> key was lost, and announce the cluster ip
def selfregister():
    global leader, leaderip, myhost, myhostip
    if not myhost or myhost == leader or not leaderip:
        return
    try:
        # the values are the node's ADDRESS ('10.11.11.27'), never its name: the old test 'myhost in str(...)' was always false for
        # ActivePartners, so a node the leader had dropped (its etcd was down for a while) never registered itself again
        active = get(leaderip, 'ActivePartners/' + myhost)[0]
        ready = get(leaderip, 'ready/' + myhost)[0]
    except Exception:
        return
    if str(active) in ('_1', '', 'None') or str(ready) not in ('_1', '', 'None'):
        return
    stampit = str(stamp())
    put(leaderip, 'ready/' + myhost, myhostip)
    put(leaderip, 'sync/ready/Add_' + myhost + '_' + myhostip + '/request', 'ready_' + stampit)
    put(leaderip, 'sync/ready/Add_' + myhost + '_' + myhostip + '/request/' + leader, 'ready_' + stampit)
    with open('/root/heartproblem', 'a') as f:
        f.write('\nselfregister: ready/' + myhost + ' was missing on ' + leaderip + ', written again\n')


def announceclusterip():
    global leader, myhost, leaderip
    if myhost != leader or not leaderip:
        return
    try:
        out = subprocess.check_output(['ip', '-o', '-4', 'route', 'show', 'to', 'match', leaderip], stderr=subprocess.DEVNULL).decode()
    except Exception:
        return
    devs = set()
    for line in out.splitlines():
        if line.startswith('default'):
            continue
        if ' dev ' in line:
            devs.add(line.split(' dev ')[1].split()[0])
    for dev_ in devs:
        subprocess.call(['arping', '-U', '-c', '1', '-I', dev_, '-s', leaderip, leaderip],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def heartbeat(*args):
    global etcd, leader ,leaderip, myhost, myhostip
    cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
    leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
    leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
    myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
    myhostip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
    nochange = 1
    knownsn =  0
    port = myport = '2379'
    if myhost == leader:
        etcd = leaderip
    else:
        etcd = myhostip
    nextleader, nextleaderip = getnextlead()
    loopcount = 0
    while True:
        print('looping')
        sleep(1)
        loopcount += 1
        if loopcount % 15 == 0:
            selfregister()
        if loopcount % 20 == 0:
            announceclusterip()
        tries = 0
        while tries < 8:
            knowns = get(etcd, 'ready','--prefix')
            if 'dhcp' in str(knowns):
                tries = 10
                break
            tries +=1
        if len(knowns) == knownsn and knownsn == 1:
            print('only one host is running..,,will do nothing')
            continue
        knownsn = len(knowns)
        if tries < 10: 
           hostlost(leader, leaderip)
        elif myhost == leader:
           leadernextlead(knowns)
        for known in knowns:
            host = known[0].split('/')[1]
            if host == myhost:
                continue
            if host == leader:
                hostip = leaderip
            else:
                hostip = known[1]
            print('nmapping')
            result = 'failed'
            tries = 0
            res = ''
            while tries < 5:
                tries +=1
                try:
                    cmdline='nmap --max-rtt-timeout 500ms -n -p '+port+' '+hostip 
                    res=subprocess.check_output(cmdline.split(),stderr=subprocess.STDOUT).decode('utf-8')
                except:
                    result=(host,'doubt')
                if portopen(hostip, port):
                    result = (host,'ok')
                else:
                    result = (host,'doubt')
                if 'doubt' in str(result):
                    print('ddddddddddddddddddddddddd')
                    cmdline='ping -w 1 '+hostip 
                    print(cmdline)
                    try:
                        subprocess.check_output(cmdline.split())
                    except subprocess.CalledProcessError as e:
                        result=(host,'lost')
                if 'ok' in str(result):
                    break
                sleep(2)
            print(result)
            if 'ok' not in str(result):
                with open('/root/heartproblem','a') as f:
                        f.write('OK:\n'+host+' '+res)
                hostlost(host, hostip)
                break
    print(leader ,leaderip, myhost, myhostip)
    return leader ,leaderip, myhost, myhostip

 


if __name__=='__main__':

 print(leader ,leaderip, myhost, myhostip)
 heartbeat(*sys.argv)
