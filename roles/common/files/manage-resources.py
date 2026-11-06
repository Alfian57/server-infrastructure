#!/usr/bin/env python3
"""Own resource changes by application; never infer deletion from a filtered catalog."""
from __future__ import annotations
import fnmatch
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

spec=importlib.util.spec_from_file_location('databases',Path(__file__).with_name('manage-databases.py'))
db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db)
BASE=Path('/opt/docker-stack/applications')
RETIRED={'posyandu','materi-ku','ruang-istirahat','tech-talk','campus-project-hub-api','campus-project-hub-web'}


def inspect_all():
    ids=db.command(['docker','ps','-aq']).stdout.split()
    return json.loads(db.command(['docker','inspect',*ids]).stdout) if ids else []


def env_file(path):
    result={}
    if path.is_file():
        for line in path.read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k,v=line.split('=',1);result[k.strip()]=v.strip().strip('"\'')
    return result


def app_directory(name):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*',name):raise ValueError('Invalid application identifier')
    path=BASE/name
    if path.is_symlink() or path.resolve()!=path:raise ValueError('Application directory must not be a symlink')
    return path


def owned_containers(name):
    path=str(app_directory(name))
    result=[]
    for c in inspect_all():
        labels=c['Config'].get('Labels') or {}
        if labels.get('com.docker.compose.project.working_dir')==path:
            result.append(c)
    return result


def preserve_images(app):
    path=app_directory(app['name'])
    containers=owned_containers(app['name'])
    services={c['Config']['Labels'].get('com.docker.compose.service'): {'image':c['Image']} for c in containers
              if c['Config']['Labels'].get('com.docker.compose.service') and 'postgres' not in c['Name']}
    if not services:return {'preserved':False}
    # JSON is a valid Compose YAML document. Keep the base file usable by CI.
    (path/'docker-compose.preserve.json').write_text(json.dumps({'services':services}))
    (path/'docker-compose.preserve.json').chmod(0o644)
    result={'preserved':True,'services':list(services)}
    if app['name']=='guardian-lab':
        stream=next((c for c in containers if c['Name'].lstrip('/')=='guardian-lab-stream'),None)
        if stream:
            digests=json.loads(db.command(['docker','image','inspect',stream['Image']]).stdout)[0].get('RepoDigests',[])
            result['stream_image']=next((d for d in digests if d.startswith('nginx@')),stream['Config']['Image'])
    return result


def request(url,method='GET',body=None,headers=None):
    headers=dict(headers or {})
    if body is not None:headers['Content-Type']='application/json'
    req=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,method=method,headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=900) as response:
            raw=response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f'Resource API returned HTTP {exc.code}: {urllib.parse.urlsplit(url).path}') from None


class PublicResources:
    def __init__(self,credentials):
        self.credentials=credentials
        token=credentials.get('cloudflare_token','')
        try:
            verify=request('https://api.cloudflare.com/client/v4/user/tokens/verify',headers={'Authorization':'Bearer '+token})
        except RuntimeError:
            verify={'success':False}
        self.cf_headers=({'Authorization':'Bearer '+token} if verify.get('success') else
                         {'X-Auth-Email':credentials['cloudflare_email'],'X-Auth-Key':credentials.get('cloudflare_global_key') or token})
        self.npm_headers=None

    def cf(self,path,method='GET',body=None):
        value=request('https://api.cloudflare.com/client/v4/'+path,method,body,self.cf_headers)
        if not value.get('success'):raise RuntimeError('Cloudflare resource request failed')
        return value['result']

    def npm(self,path,method='GET',body=None):
        if self.npm_headers is None:
            value=request('http://127.0.0.1:81/api/tokens','POST',{'identity':self.credentials['npm_email'],'secret':self.credentials['npm_password']})
            self.npm_headers={'Authorization':'Bearer '+value['token']}
        return request('http://127.0.0.1:81/api/'+path,method,body,self.npm_headers)

    def zone(self,domain):
        values=self.cf('zones?name='+urllib.parse.quote(domain))
        if len(values)!=1:raise ValueError('Exactly one authorized DNS zone is required')
        return values[0]['id']

    def records(self,app):
        entries=app.get('dns',[])
        if isinstance(entries,dict):entries=[entries]
        for entry in entries:
            zone=self.zone(entry['domain'])
            for record in entry.get('records',[]):
                full=entry['domain'] if record=='@' else (record if record.endswith('.'+entry['domain']) else record+'.'+entry['domain'])
                yield zone,full

    def host_definitions(self,app):
        hosts=app.get('proxy_hosts',[])+([app['proxy']] if app.get('proxy') else [])
        result=[]
        for h in hosts:
            value=dict(h)
            domain=h.get('domain') or h['subdomain']+'.alfian-gading.my.id'
            value['domain_names']=list(dict.fromkeys((h.get('domains') or [domain])+h.get('additional_domains',[])))
            result.append(value)
        return result

    def upsert(self,app,address,*,dns_only=False):
        state=db.read_state();claim=state['applications'].get(app['name'],{})
        requested={d for h in self.host_definitions(app) for d in h['domain_names']}
        for name,owned in state['applications'].items():
            if name==app['name']:continue
            other={r['name'] for r in owned.get('dns',[])} | {d for h in owned.get('proxies',[]) for d in h['domains']}
            if requested & other:raise ValueError('Public resource is owned by another application')
        dns=[]
        for zone,full in self.records(app):
            current=self.cf(f'zones/{zone}/dns_records?name='+urllib.parse.quote(full))
            relevant=[r for r in current if r['type'] in ('A','CNAME')]
            if len(relevant)>1:raise ValueError('Multiple address records require explicit reconciliation: '+full)
            record=relevant[0] if relevant else None
            desired={'type':'A','name':full,'content':address,'proxied':True,'ttl':1,'comment':f"ansible:{app['group']}:{app['name']}"}
            if not record or any(record.get(k)!=v for k,v in desired.items()):
                record=self.cf(f'zones/{zone}/dns_records'+('/'+record['id'] if record else ''),'PUT' if record else 'POST',desired)
            dns.append({'zone':zone,'name':full,'id':record['id']})
        if dns_only:
            state['applications'].setdefault(app['name'],{'group':app['group']})['dns']=dns
            db.save_state(state)
            return {'application':app['name'],'dns_records':len(dns)}
        definitions=self.host_definitions(app)
        proxies=[]
        if definitions:
            existing=self.npm('nginx/proxy-hosts');certs=self.npm('nginx/certificates')
            own_domains={d for h in definitions for d in h['domain_names']}
            for h in definitions:
                matches=[p for p in existing if set(p['domain_names'])&set(h['domain_names'])]
                if len(matches)>1:raise ValueError('Domain is attached to multiple proxy hosts')
                current=matches[0] if matches else None
                if current and not set(current['domain_names'])<=own_domains:
                    raise ValueError('Proxy host also serves another application; refusing to change it')
                certificate=current.get('certificate_id',0) if current else 0
                if not certificate:
                    for c in certs:
                        if all(any(fnmatch.fnmatchcase(d,p) for p in c['domain_names']) for d in h['domain_names']):
                            certificate=c['id'];break
                if not certificate:
                    token=self.credentials['cloudflare_token']
                    credentials=('dns_cloudflare_api_token='+token if 'Authorization' in self.cf_headers else
                                 'dns_cloudflare_email='+self.credentials['cloudflare_email']+'\ndns_cloudflare_api_key='+(self.credentials.get('cloudflare_global_key') or token))
                    c=self.npm('nginx/certificates','POST',{'provider':'letsencrypt','domain_names':h['domain_names'],
                               'meta':{'dns_challenge':True,'key_type':'rsa','dns_provider':'cloudflare','propagation_seconds':120,'dns_provider_credentials':credentials}})
                    certificate=c['id'];certs.append(c)
                body={k:current[k] for k in ['domain_names','forward_scheme','forward_host','forward_port','access_list_id','certificate_id','ssl_forced','caching_enabled','block_exploits','allow_websocket_upgrade','http2_support','hsts_enabled','hsts_subdomains','advanced_config','locations','meta','enabled'] if current and k in current}
                body.update({'domain_names':h['domain_names'],'forward_scheme':h.get('scheme','http'),'forward_host':h['forward_host'],
                             'forward_port':int(h['forward_port']),'certificate_id':certificate,'enabled':True})
                if not current:
                    body.update({'ssl_forced':True,'caching_enabled':h.get('caching_enabled',False),'block_exploits':True,
                                 'allow_websocket_upgrade':h.get('websocket_support',True),'http2_support':True,'hsts_enabled':True,
                                 'hsts_subdomains':False,'access_list_id':0,'locations':[],'meta':{},'advanced_config':h.get('advanced_config','')})
                # NPM 2.14 supports forwarding the original Cloudflare scheme.
                version=db.command(['docker','exec','nginx-proxy-manager','node','-p',"require('/app/package.json').version"]).stdout.strip()
                if tuple(int(x) for x in version.split('.')[:2]) >= (2,14):body['trust_forwarded_proto']=True
                if not current or any(current.get(k)!=v for k,v in body.items()):
                    current=self.npm('nginx/proxy-hosts'+('/'+str(current['id']) if current else ''),'PUT' if current else 'POST',body)
                proxies.append({'id':current['id'],'domains':h['domain_names']})
                if h.get('disable_error_log'):
                    script="const fs=require('fs');const p='/data/nginx/proxy_host/'+process.argv[1]+'.conf';let s=fs.readFileSync(p,'utf8');s=s.replace(/(^|\\n)(\\s*)error_log\\s+[^;]+;/g,'$1$2error_log /dev/null crit;');fs.writeFileSync(p,s);"
                    db.command(['docker','exec','nginx-proxy-manager','node','-e',script,str(current['id'])])
                    db.command(['docker','exec','nginx-proxy-manager','sh','-c','nginx -t && nginx -s reload'])
        state=db.read_state()
        state['applications'][app['name']]={'group':app['group'],'dns':dns,'proxies':proxies,'enabled':True}
        db.save_state(state)
        return {'application':app['name'],'dns_records':len(dns),'proxy_hosts':len(proxies)}

    def remove(self,app):
        allowed={d for h in self.host_definitions(app) for d in h['domain_names']}
        for zone,full in self.records(app):
            for record in self.cf(f'zones/{zone}/dns_records?name='+urllib.parse.quote(full)):
                if record['name']==full and record['type'] in ('A','CNAME'):
                    self.cf(f'zones/{zone}/dns_records/'+record['id'],'DELETE')
        for host in self.npm('nginx/proxy-hosts'):
            remaining=[d for d in host['domain_names'] if d not in allowed]
            if len(remaining)==len(host['domain_names']):continue
            if not remaining:self.npm('nginx/proxy-hosts/'+str(host['id']),'DELETE')
            else:
                keys=['domain_names','forward_scheme','forward_host','forward_port','access_list_id','certificate_id','ssl_forced','caching_enabled','block_exploits','allow_websocket_upgrade','http2_support','hsts_enabled','hsts_subdomains','advanced_config','locations','meta','enabled']
                body={k:host[k] for k in keys if k in host};body['domain_names']=remaining
                self.npm('nginx/proxy-hosts/'+str(host['id']),'PUT',body)
        remaining_ids={h.get('certificate_id') for h in self.npm('nginx/proxy-hosts')}
        for cert in self.npm('nginx/certificates'):
            if cert.get('domain_names') and set(cert['domain_names'])<=allowed and cert['id'] not in remaining_ids:
                self.npm('nginx/certificates/'+str(cert['id']),'DELETE')


def protected_databases():
    result={'postgres':set(),'mysql':set()}
    for path in BASE.iterdir():
        if not path.is_dir() or path.name in RETIRED:continue
        env=env_file(path/'.env')
        database=env.get('DB_DATABASE') or env.get('DB_NAME')
        if database:
            engine='postgres' if 'postgres' in env.get('DB_HOST','') or env.get('DB_CONNECTION') in ('pgsql','postgres') else 'mysql'
            result[engine].add(database)
        for key in ('DATABASE_URL','API_DATABASE_URL','ROUTER_DATABASE_URL'):
            value=env.get(key,'')
            if value.startswith(('postgres://','postgresql://','mysql://')):
                parsed=urllib.parse.urlsplit(value)
                result['mysql' if parsed.scheme=='mysql' else 'postgres'].add(parsed.path.lstrip('/'))
    return result


def cleanup_redis(app,env,containers):
    if 'redis_network' not in app.get('networks',[]):return 0
    prefixes=set()
    # Laravel provides the effective prefixes even when config is cached.
    code=("$app=require 'bootstrap/app.php';$app->make(Illuminate\\Contracts\\Console\\Kernel::class)->bootstrap();"
          "echo json_encode(['redis'=>config('database.redis.options.prefix'),'cache'=>config('cache.prefix'),"
          "'db'=>config('database.redis.cache.database',1)]);")
    database=env.get('REDIS_CACHE_DB','1')
    for c in containers:
        if app.get('stack')!='laravel':continue
        p=db.command(['docker','exec',c['Id'],'php','-r',code],check=False)
        if p.returncode==0:
            try:
                value=json.loads(p.stdout);prefix=str(value.get('redis') or '')+str(value.get('cache') or '')
                if prefix:prefixes.add(prefix);database=str(value['db'])
            except (ValueError,KeyError):pass
    if env.get('REDIS_PREFIX') and env.get('CACHE_PREFIX'):
        prefixes.add(env['REDIS_PREFIX']+env['CACHE_PREFIX'])
    if not prefixes:return 0
    retained_prefixes=set()
    for path in BASE.iterdir():
        if not path.is_dir() or path.name in RETIRED:continue
        other=env_file(path/'.env')
        if other.get('REDIS_PREFIX') and other.get('CACHE_PREFIX'):
            retained_prefixes.add(other['REDIS_PREFIX']+other['CACHE_PREFIX'])
    if prefixes & retained_prefixes:raise ValueError('Redis namespace is shared; refusing to delete it')
    redis_env=db.environment('redis-server')
    auth=redis_env.get('REDIS_PASSWORD','')
    # Most deployments pass the password through .env rather than container Env.
    auth=auth or env.get('REDIS_PASSWORD','') or env_file(Path('/opt/docker-stack/databases/redis/.env')).get('REDIS_PASSWORD','')
    count=0
    for prefix in prefixes:
        pattern=''.join('\\'+c if c in '*?[]\\' else c for c in prefix)+'*'
        args=['docker','exec','-e','REDISCLI_AUTH='+auth,'redis-server','redis-cli','-n',database]
        keys=db.command(args+['--scan','--pattern',pattern]).stdout.splitlines()
        for offset in range(0,len(keys),100):
            batch=keys[offset:offset+100]
            if batch:db.command(args+['UNLINK',*batch]);count+=len(batch)
    return count


def decommission(payload):
    if not payload.get('confirm_destroy_data'):raise ValueError('Explicit data deletion confirmation is required')
    state=db.read_state();protected=protected_databases()
    # Validate the complete target set before removing any container or database.
    for app in payload['applications']:
        if app['name'] not in RETIRED:raise ValueError('Not in the authorized retirement set')
        env=env_file(app_directory(app['name'])/'.env')
        claims={k:list(v) for k,v in app.get('databases',{}).items()}
        actual=env.get('DB_DATABASE') or env.get('DB_NAME')
        if actual:claims.setdefault('postgres' if 'postgres' in env.get('DB_HOST','') else 'mysql',[]).append(actual)
        for engine,names in claims.items():
            for database in names:
                if database in protected.get(engine,set()) or database in payload.get('retained_databases',{}).get(engine,[]):raise ValueError('Database is still claimed by a retained application')
                owner=state['databases'].get(engine+':'+database)
                if owner and owner['app']!=app['name']:raise ValueError('Database belongs to another application')
                if database in ('postgres','mysql','template0','template1','sys','information_schema','performance_schema'):raise ValueError('System database deletion prohibited')
    public=PublicResources(payload['credentials']);results=[]
    for app in payload['applications']:
        name=app['name']
        if name not in RETIRED:raise ValueError('Not in the authorized retirement set')
        path=app_directory(name);env=env_file(path/'.env');containers=owned_containers(name)
        redis_keys=cleanup_redis(app,env,containers)
        volumes={m['Name'] for c in containers for m in c['Mounts'] if m['Type']=='volume'}
        # Legacy volumes may remain after a disabled application's container was removed.
        for volume in db.command(['docker','volume','ls','-q']).stdout.split():
            info=json.loads(db.command(['docker','volume','inspect',volume]).stdout)[0]
            labels=info.get('Labels') or {}
            declared={v.split(':',1)[0] for v in app.get('volumes',[]) if not v.startswith(('/','.'))}
            if labels.get('com.docker.compose.project')==name or volume in declared or volume in {name+'_'+v for v in declared}:
                volumes.add(volume)
        for c in containers:db.command(['docker','rm','-f',c['Id']])
        databases={engine:set(values) for engine,values in app.get('databases',{}).items()}
        configured=env.get('DB_DATABASE') or env.get('DB_NAME')
        if configured:
            engine='postgres' if 'postgres' in env.get('DB_HOST','') else 'mysql'
            databases.setdefault(engine,set()).add(configured)
        for engine,names in databases.items():
            for database in names:
                if '{{' in database:continue
                if database in payload.get('retained_databases',{}).get(engine,[]):raise ValueError('Database is still claimed by a retained application')
                claim=state['databases'].get(engine+':'+database)
                if claim and claim['app']!=name:raise ValueError('Database belongs to another application')
                if database in ('postgres','mysql','template0','template1','sys','information_schema','performance_schema'):raise ValueError('System database deletion prohibited')
                if engine=='postgres':
                    db.pg('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='+db.literal(database)+' AND pid<>pg_backend_pid();')
                    db.pg('DROP DATABASE IF EXISTS '+db.ident(database))
                else:db.mysql('DROP DATABASE IF EXISTS `'+database.replace('`','``')+'`')
                state['databases'].pop(engine+':'+database,None)
        username=env.get('DB_USERNAME') or env.get('DB_USER')
        if username and username not in ('root','postgres',db.environment('postgres-db').get('POSTGRES_USER')):
            if 'postgres' in env.get('DB_HOST',''):
                dependencies=db.pg('SELECT count(*) FROM pg_shdepend WHERE refobjid=(SELECT oid FROM pg_roles WHERE rolname='+db.literal(username)+')').stdout.strip()
                if dependencies=='0':db.pg('DROP ROLE IF EXISTS '+db.ident(username))
            else:
                grants=db.mysql('SELECT TABLE_SCHEMA FROM information_schema.SCHEMA_PRIVILEGES WHERE GRANTEE='+db.literal("'"+username+"'@'%'")).stdout.splitlines()
                if not [g for g in grants if g not in databases.get('mysql',set())]:
                    # Never delete a global/administrative account.
                    global_grants=db.mysql('SELECT PRIVILEGE_TYPE FROM information_schema.USER_PRIVILEGES WHERE GRANTEE='+db.literal("'"+username+"'@'%'")+" AND PRIVILEGE_TYPE<>'USAGE'").stdout.strip()
                    if not global_grants:db.mysql('DROP USER IF EXISTS '+db.literal(username)+"@'%'")
        for volume in volumes:
            remaining=[c for c in inspect_all() if any(m.get('Name')==volume for m in c['Mounts'])]
            if remaining:raise ValueError('Volume is still mounted by another application')
            db.command(['docker','volume','rm',volume])
        public.remove(app)
        if path.exists():shutil.rmtree(path)
        for log in Path('/var/log/docker-updates').glob(name+'.log*'):
            if log.is_file() or log.is_symlink():log.unlink()
        for backup_root in (Path('/opt/docker-stack/backups'),Path('/var/backups/docker-stack')):
            target=backup_root/name
            if target.is_dir() and not target.is_symlink():shutil.rmtree(target)
        state['applications'].pop(name,None)
        results.append({'application':name,'removed_databases':{k:sorted(v) for k,v in databases.items()},'removed_volumes':sorted(volumes),'removed_redis_keys':redis_keys})
    db.save_state(state)
    receipt=Path('/opt/docker-stack/.state/decommission.json')
    receipt.write_text(json.dumps(results,indent=2));receipt.chmod(0o640)
    return results


def cleanup_postgres():
    removed=[]
    for name,volume in [('aldera-router-postgres','aldera_router_postgres_data'),('aldera-router-staging-postgres','aldera_router_staging_postgres_data')]:
        candidates=[c for c in inspect_all() if c['Name'].lstrip('/')==name]
        for c in candidates:
            expected=str(BASE/('aldera-router-staging' if 'staging' in name else 'aldera-router'))
            if c['Config'].get('Labels',{}).get('com.docker.compose.project.working_dir')!=expected:raise ValueError('Unexpected PostgreSQL source owner')
            db.command(['docker','rm','-f',name])
        if db.command(['docker','volume','inspect',volume],check=False).returncode==0:
            if any(m.get('Name')==volume for c in inspect_all() for m in c['Mounts']):raise ValueError('Source volume remains in use')
            db.command(['docker','volume','rm',volume]);removed.append(volume)
    return {'removed_sources':removed}


def main():
    payload=json.load(sys.stdin);operation=payload['operation']
    if operation=='preserve':return preserve_images(payload['application'])
    if operation in ('public','dns'):return PublicResources(payload['credentials']).upsert(payload['application'],payload['address'],dns_only=operation=='dns')
    if operation=='decommission':return decommission(payload)
    if operation=='cleanup-postgres':return cleanup_postgres()
    if operation=='initialized':
        state=db.read_state()
        for claim in state['databases'].values():
            if claim['app']==payload['application']['name']:claim['initialized']=True
        db.save_state(state)
        return {'initialized':payload['application']['name']}
    raise ValueError('Unknown resource operation')


if __name__=='__main__':
    try:print(json.dumps(main()))
    except (ValueError,RuntimeError,OSError,KeyError) as exc:
        print(type(exc).__name__+': '+str(exc),file=sys.stderr);sys.exit(1)
