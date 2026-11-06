#!/usr/bin/env python3
"""Run scoped Ansible while a persistent SSH session holds the VPS deployment lock."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import threading
import time

from catalog import ROOT, index, select


def inventory_host() -> dict:
    result = subprocess.run(['ansible-inventory', '--list'], cwd=ROOT, check=True, capture_output=True, text=True)
    hosts = json.loads(result.stdout)['_meta']['hostvars']
    if len(hosts) != 1:
        raise ValueError('Deployment requires an inventory containing exactly one VPS')
    name, values = next(iter(hosts.items()))
    return {'name':name, **values}


def ssh_args(host: dict) -> list[str]:
    args = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20',
            '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3',
            '-p', str(host.get('ansible_port', 22))]
    if host.get('ansible_ssh_private_key_file'):
        args += ['-i', str(Path(host['ansible_ssh_private_key_file']).expanduser())]
    # CI supplies an explicitly pinned known_hosts file; never use ssh-keyscan.
    if os.environ.get('VPS_KNOWN_HOSTS_FILE'):
        args += ['-o', 'UserKnownHostsFile='+os.environ['VPS_KNOWN_HOSTS_FILE']]
    args += [f"{host.get('ansible_user', 'deployer')}@{host.get('ansible_host',host['name'])}"]
    return args


def run(args) -> int:
    if args.operation not in ('deploy','check','dns') and (args.group or args.app):
        raise ValueError('This operation has a fixed platform target; do not supply --group or --app')
    if args.operation in ('deploy','check','dns'):
        selected = select(args.group,args.app,require_target=True,enabled_only=True,default_only=True)
        if not selected:raise ValueError('No enabled applications match the target')
        group = selected[0]['group']
    else:
        group = 'alderatech' if args.operation == 'consolidate' else args.group
        if args.operation == 'platform' and not args.service:
            raise ValueError('platform requires --service')
        if args.operation == 'decommission' and not args.destroy_data:
            raise ValueError('decommission requires --destroy-data')
    host=inventory_host()
    script=(ROOT/'roles/common/files/with-deployment-lock.sh').read_text()
    # OpenSSH can set O_NONBLOCK on inherited stderr. Give it a separate pipe:
    # Ansible requires its own inherited stdin/stdout/stderr to stay blocking.
    holder=subprocess.Popen(ssh_args(host)+['bash -c '+shlex.quote(script)+' -- --hold'], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def forward_ssh_errors():
        for line in holder.stderr:
            sys.stderr.write(line)
            sys.stderr.flush()
    errors=threading.Thread(target=forward_ssh_errors,daemon=True)
    errors.start()
    child=None
    try:
        line=holder.stdout.readline().strip()
        if not line.startswith('LOCKED '):
            raise RuntimeError('Unable to acquire the VPS deployment lock')
        token=line.split()[1]
        playbook={'deploy':'deploy-group','check':'deploy-group','platform':'platform','preflight':'preflight',
                  'decommission':'decommission','consolidate':'consolidate-postgres','helpers':'install-helpers','dns':'public-hosts'}[args.operation]
        extra={'deployment_group':group,'app':args.app,'infra_lock_token':token,'platform_service':args.service,
               'confirm_destroy_data':args.destroy_data,'dns_only':args.operation=='dns'}
        command=['ansible-playbook','playbooks/'+playbook+'.yml','--extra-vars',json.dumps(extra)]
        if args.operation=='check':command+=['--check']
        child=subprocess.Popen(command,cwd=ROOT)
        while child.poll() is None:
            if holder.poll() is not None:
                child.terminate()
                raise RuntimeError('VPS lock connection was lost; Ansible has been stopped')
            time.sleep(.25)
        return child.returncode
    finally:
        if child and child.poll() is None:
            child.terminate()
            try:child.wait(timeout=15)
            except subprocess.TimeoutExpired:child.kill();child.wait()
        if holder.stdin:holder.stdin.close()
        try:holder.wait(timeout=15)
        except subprocess.TimeoutExpired:holder.terminate();holder.wait()
        errors.join(timeout=5)
        holder.stdout.close()
        holder.stderr.close()


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation',choices=['deploy','check','platform','preflight','decommission','consolidate','helpers','dns','all','rollout','resume-rollout'])
    p.add_argument('--group',default='')
    p.add_argument('--app',default='')
    p.add_argument('--service',default='')
    p.add_argument('--destroy-data',action='store_true')
    a=p.parse_args()
    try:
        if a.operation in ('rollout','resume-rollout'):
            if not a.destroy_data or a.group or a.app or a.service:
                raise ValueError('rollout has fixed targets and requires --destroy-data')
            steps=[('helpers',''),('deploy','uty'),('decommission',''),('consolidate',''),
                   ('deploy','personal'),('deploy','lomba'),('deploy','gamblock-ai'),('preflight','')]
            if a.operation=='resume-rollout':steps=steps[3:]
            for operation,group in steps:
                step=argparse.Namespace(**vars(a));step.operation=operation;step.group=group
                step.destroy_data=operation in ('decommission','consolidate')
                print('Applying operation '+operation+(' group='+group if group else ''),flush=True)
                status=run(step)
                if status:return status
            return 0
        if a.operation=='all':
            if a.group or a.app or a.service or a.destroy_data:
                raise ValueError('all cannot be combined with another target selector')
            for group in index()['groups']:
                a.operation='deploy';a.group=group
                status=run(a)
                if status:return status
            return 0
        return run(a)
    except (ValueError,RuntimeError,subprocess.CalledProcessError) as exc:p.exit(2,str(exc)+'\n')


if __name__=='__main__':raise SystemExit(main())
