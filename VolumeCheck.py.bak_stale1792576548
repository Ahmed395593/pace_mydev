#!/usr/bin/python3
import subprocess,sys, os
from etcdgetpy import etcdget as get
from etcdput import etcdput as put 
from etcddel import etcddel as dels 
#from broadcasttolocal import broadcasttolocal 
from time import time as stamp
from glob import glob
import json
from concurrent.futures import ThreadPoolExecutor

# QSD5.330: after a take-over every dirty volume is started in parallel.  Volumes that share an address are
# processed one after the other (cifs.py also takes a per-address lock); the volume types run side by side.
def runbygroup(items, keyf, worker):
    groups = {}
    for it in items:
        groups.setdefault(keyf(it), []).append(it)
    def rungroup(g):
        for it in g:
            try:
                worker(it)
            except Exception as e:
                print('volume worker failed', it, e)
    if not groups:
        return
    with ThreadPoolExecutor(max_workers=len(groups)) as ex:
        list(ex.map(rungroup, groups.values()))

_inspectcache = {}
def inspectall(dockers):
    # one docker inspect for all running containers (was one call per volume)
    global _inspectcache
    names = [l.split(' ')[-1] for l in dockers.split('\n')[1:] if l.strip()]
    _inspectcache = {}
    if not names:
        return
    out = subprocess.run(['docker','inspect']+names,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout.decode('utf-8')
    try:
        for d in json.loads(out):
            _inspectcache[d['Name'].lstrip('/')] = json.dumps(d)
    except Exception:
        _inspectcache = {}

def inspectone(dckrname):
    if dckrname in _inspectcache:
        return _inspectcache[dckrname]
    cmdline = 'docker inspect '+dckrname
    return subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')


#leader=get('leader','--prefix')[0][0].split('/')[1]

def dosync(*args):
  global leaderip, leader
  put(leaderip, *args)
  put(leaderip, args[0]+'/'+leader,args[1])
  return 

def getippos(vtype):
    print('vtype',vtype)
    if vtype in ['cifs', 'home']:
        return 7
    elif 'nfs' in vtype:
        return 9
    else: 
        return 0
def getdirtyvols(vtype, etcds, replis, dockers):
    global leader, leaderip, myhost, myhostip, etcdip
    cmdline = '/TopStor/getvols.sh '+vtype
    result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
    result = [x for x in result if 'pdhc' in x]
    resultdisabled = [ x for x in result if 'disable' in str(x) ]
    resultactive = [ x for x in result if 'active' in str(x) ]
    etcddisabled= [ x for x in etcds if 'disable' in str(x) ]
    etcdactive= [ x for x in etcds if 'active' in str(x) ]
    dirtyset = set()
    ipset = set()
    for res in result:
        reslist=res.split('/')
        ippos = getippos(vtype)
        if reslist[-1] == 'active':
            if reslist[1] in str(etcddisabled):
                dirtyset.add(res)
        else:
            if reslist[1] in str(etcdactive):
                dirtyset.add(res)
                print('here2', res)
        if reslist[1] not in str(etcds):
            dirtyset.add(res)
        for dckr in dockers.split('\n'):
            dckrip = dckr.split(' ')[-1].split('-')[-1]
            if dckrip != reslist[ippos]:
                continue
            if reslist[ippos] in dckr and reslist[-1] =='active':
                dckrname=dckr.split(' ')[-1]
                result = inspectone(dckrname)
                print(dckrname, reslist[1],reslist)
                if reslist[1] not in str(result):
                    print('gggggggggggggggggggggggggggggggggggggggggg')
                    print('not in',ippos, reslist[ippos], dckrip)
                    print('reslist1',reslist[1], dckrname)
                    print('gggggggggggggggggggggggggggggggggggggggggg')
                    dirtyset.add(res)
        if reslist[ippos] not in dockers and 'active' in reslist[-1]:
            dirtyset.add(res)
    print('dirtyset', dirtyset)
    return dirtyset

def nfs( etcds, replis, exports):
    global leader, leaderip, myhost, myhostip, etcdip
    #dirtyset = getdirtyvols('nfs', etcds, replis, )
    flag = 0
    for export in exports:
        with open(export) as f:
            pool = export.split('/')[1]
            vol = export.split('.')[1]
            print(pool,vol)
            exportetctip = 0
            for line in f:
                if len(line) < 5:
                    continue
                print('theline',line)
                if 'SUMMARY' in line:
                    exportetc = line.split(' ')[3]
                    exportetcip = exportetc.split('/')[-3]
                    exportetcsub = exportetc.split('/')[-2]
                    exportetcactive = exportetc.split('/')[-1]
                    if exportetc[2:-2] not in str(etcds):
                        dels(leaderip, 'volumes', vol)
                        put(leaderip,'volumes/NFS/'+myhost+'/'+pool+'/'+vol,exportetc)
                        flag = 1
                else:
                    if 'active' in exportetcactive: 
                        with open('/TopStordata/exportip.'+vol+'_'+exportetcip, 'w') as fip:
                            fip.write(line)
                        cmdline = '/TopStor/nfs.sh '+exportetcip+' '+exportetcsub
                        subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
                    else:
                        cmdline = '/TopStor/nfsumount.sh '+vol
                        subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    if flag:
        dosync('sync/volumes/_'+myhost+'/request','volumes_'+str(stamp()))
        
    return    

def nfsnew( etcds, replis, dockers):
 global leader, leaderip, myhost, myhostip, etcdip
 dirtyset = getdirtyvols('nfs', etcds, replis, dockers)
 print('cccccccccccccccccccccccccccccc')
 print('dirty',dirtyset)
 print('cccccccccccccccccccccccccccccc')
 def one(res):
   reslist=res.split('/')
   print('update',reslist[1])
   cmdline = '/TopStor/undockerthis.sh '+reslist[getippos('nfs')]
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   left='volumes/NFS/'+myhost+'/'+'/'.join(reslist[0:2])
   put(leaderip, left,res)
   dosync('sync/volumes/_'+myhost+'/request','volumes_'+str(stamp()))
   cmdline='/TopStor/nfsnew.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+etcdip+' '+reslist[0]+' '+reslist[1]+' '+reslist[9]+' '+reslist[10]+' NFS'
   print('aloooooooooooooooooooooo')
   print(cmdline)
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   put(etcdip,'dirty/volume','0')
 runbygroup(sorted(dirtyset), lambda r: r.split('/')[getippos('nfs')], one)

def cifs( etcds, replis, dockers):
 global leader, leaderip, myhost, myhostip, etcdip
 dirtyset = getdirtyvols('cifs', etcds, replis, dockers)
 print('cccccccccccccccccccccccccccccc')
 print('dirty',dirtyset)
 print('cccccccccccccccccccccccccccccc')
 def one(res):
   reslist=res.split('/')
   print('update',reslist[1])
   cmdline = '/TopStor/undockerthis.sh '+reslist[7]
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   if 'DOMAIN' in str(res):
    left='volumes/CIFS_'+reslist[9]+'/'+myhost+'/'+'/'.join(reslist[0:2])
   else:
    left='volumes/CIFS/'+myhost+'/'+'/'.join(reslist[0:2])
   put(leaderip, left,res)
   print('tosync this',leaderip, left,res)
   dosync('sync/volumes/_'+myhost+'/request','volumes_'+str(stamp()))
   if 'DOMAIN' in str(res):
     cmdline='/TopStor/cifs.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+etcdip+' '+reslist[0]+' '+reslist[1]+' '+reslist[7]+' '+reslist[8]+' CIFS_'+reslist[9]+' '+' '.join(reslist[9:])

   else:
    cmdline='/TopStor/cifs.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+etcdip+' '+reslist[0]+' '+reslist[1]+' '+reslist[7]+' '+reslist[8]+' CIFS '+' '.join(reslist[9:])
    print('cif cifs: '+cmdline)
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   print('cifs result',result)
   put(etcdip,'dirty/volume','0')
 runbygroup(sorted(dirtyset), lambda r: r.split('/')[7], one)

def homes(etcds, replis, dockers):
 global leader, leaderip, myhost, myhostip, etcdip
 print('----------------')
 dirtyset = getdirtyvols('home', etcds, replis, dockers)
 print('hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh')
 print('dirty',dirtyset)
 print('hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh')
 def one(res):
   reslist=res.split('/')
   print('update',reslist[1])
   cmdline = '/TopStor/undockerthis.sh '+reslist[7]
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   left='volumes/HOMEE/'+myhost+'/'+'/'.join(reslist[0:2])
   put(leaderip, left,res)
   dosync('sync/volumes/_'+myhost+'/request','volumes_'+str(stamp()))
   cmdline='/TopStor/cifs.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+etcdip+' '+reslist[0]+' '+reslist[1]+' '+reslist[7]+' '+reslist[8]+' HOMEE '+' '.join(reslist[9:])
   print('home cifs: '+cmdline)
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
   print('result',result)
   put(etcdip,'dirty/volume','0')
 runbygroup(sorted(dirtyset), lambda r: r.split('/')[7], one)


def iscsi(etcds, replis):
 global leader, leaderip, myhost, myhostip, etcdip
 cmdline = 'targetcli ls '
 targets = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8') 
 cmdline = '/TopStor/getvols.sh iscsi'
 result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
 result = [x for x in result if 'pdhc' in x]
 for res in result:
  reslist=res.split('/')
  print('reslist1',reslist[1])
  if reslist[1] not in str(etcds):
   left='volumes/ISCSI/'+myhost+'/'+'/'.join(reslist[0:2])
   put(leaderip, left,res)
   dosync('sync/volumes/_'+myhost+'/request','volumes_'+str(stamp()))
   #broadcasttolocal(left,res)
  if reslist[1] not in targets:
   print(reslist)
   cmdline='/TopStor/iscsi.py '+leader+' '+leaderip+' '+myhost+' '+myhostip+' '+etcdip+' '+reslist[0]+' '+reslist[1]+' '+reslist[2]+' '+reslist[3]+' ISCSI '+reslist[4]+' '+reslist[5]+' '+reslist[6]+' '+reslist[7]
   result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')

def cleanfailed(dockers):
    fails = ['timeerror','ADnameerror', 'ADservererror']
    doms = [ (doc.split('-')[-1],doc.split(' ')[0]) for doc in dockers.split('\n') if 'CIFS_' in str(doc)]
    for dom in doms:
        cmdline = '/TopStor/getdomvolstatus.sh '+dom[0]
        result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('_result')[1]
        print('dock:',cmdline,'....',result)
        if result in fails:
            print('cleaning',dom[0],dom[1])
            cmdline = 'docker rm -f '+ dom[1]
            result = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
    
def volumecheck(etcds, replis, *args):
 global leader, leaderip, myhost, myhostip, etcdip
 if str(etcds)=='init':
     leader = replis 
     leaderip = args[0]
     myhost = args[1]
     myhostip = args[2]
     etcdip = args[3]
     return

 cmdline = 'docker ps'
 dockers = subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8') 
 #cmdline = 'ls /TopStordata'
 #exports = subprocess.run(cmdline.split(),shell=True, stdout=subprocess.PIPE).stdout.decode('utf-8')
 #cmdline = 'rm -rf /TopStordata/exportip*'
 #subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8') 
 #exports = glob('/pdhc*/exports*')
 with open('/root/volumecheck','w') as f:
  f.write(str(etcds))
 #exports = [ x.split('exports.')[1] for x in exports ]
 print('----------------------------------------------------')
 print(etcds,'\n',dockers)
 inspectall(dockers)
 jobs = [lambda: nfsnew(etcds, replis, dockers), lambda: cifs(etcds, replis, dockers),
         lambda: homes(etcds, replis, dockers), lambda: iscsi(etcds, replis)]
 def runjob(j):
     try:
         j()
     except Exception as e:
         print('volumecheck job failed', e)
 with ThreadPoolExecutor(max_workers=len(jobs)) as ex:
     list(ex.map(runjob, jobs))
 cleanfailed(dockers) 
   
if __name__=='__main__':
  leaderip = sys.argv[1]
  myhost = sys.argv[2]
  leader=get(leaderip, 'leader')[0]
  myhostip=get(leaderip,'ready/'+myhost)[0] 
  if myhost == leader:
   etcdip = leaderip
  else:
   etcdip = myhostip
   
 
  etcds = get(etcdip, 'volumes','--prefix')
  replis = get(etcdip, 'replivol','--prefix')
  volumecheck(etcds, replis)
