#!/usr/bin/env python3
"""Read-only host metadata. Never emits container environment or database content."""
import json
from pathlib import Path
import subprocess


def run(args):
    return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL)


ids=run(['docker','ps','-aq']).split()
containers=json.loads(run(['docker','inspect',*ids])) if ids else []
report={'containers':[], 'applications':[], 'postgres':[], 'disk':run(['df','-h','/opt/docker-stack']),
        'memory':run(['free','-m'])}
for c in containers:
    name=c['Name'].lstrip('/')
    report['containers'].append({'name':name,'container_id':c['Id'],'started_at':c['State']['StartedAt'],'image':c['Config']['Image'],'image_id':c['Image'],
        'status':c['State']['Status'],'health':c['State'].get('Health',{}).get('Status'),
        'project':c['Config'].get('Labels',{}).get('com.docker.compose.project'),
        'directory':c['Config'].get('Labels',{}).get('com.docker.compose.project.working_dir'),
        'volumes':[m.get('Name',m['Source']) for m in c['Mounts']]})
    if 'postgres' in name and c['State']['Running']:
        env=dict(x.split('=',1) for x in c['Config']['Env'] if '=' in x)
        user=env.get('POSTGRES_USER','postgres')
        try:
            rows=run(['docker','exec','--user','postgres',name,'psql','-U',user,'-d','postgres','-At','-c',
                      "SELECT datname || '|' || pg_database_size(oid)::text FROM pg_database WHERE NOT datistemplate ORDER BY datname"])
            version=run(['docker','exec',name,'postgres','--version']).strip()
            report['postgres'].append({'container':name,'version':version,'databases':rows.splitlines()})
        except subprocess.CalledProcessError:
            report['postgres'].append({'container':name,'metadata_unavailable':True})
for directory in sorted(Path('/opt/docker-stack/applications').glob('*')):
    if not directory.is_dir():continue
    env={}
    if (directory/'.env').is_file():
        for line in (directory/'.env').read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k,v=line.split('=',1);env[k.strip()]=v.strip().strip('"\'')
    report['applications'].append({'name':directory.name,'has_compose':(directory/'docker-compose.yml').exists(),
        'has_env':(directory/'.env').exists(),
        'database':env.get('DB_DATABASE',env.get('DB_NAME')),
        'db_host':env.get('DB_HOST'),
        'privileged_db_user':env.get('DB_USERNAME',env.get('DB_USER')) in ('root','postgres')})
print(json.dumps(report,indent=2))
