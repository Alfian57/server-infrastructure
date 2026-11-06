#!/usr/bin/env python3
"""Provision selected databases only; credentials are read on stdin and never logged."""
import json
from pathlib import Path
import subprocess
import sys

STATE = Path('/opt/docker-stack/.state/resources.json')


def command(args, stdin=None, *, check=True):
    p=subprocess.run(args,input=stdin,text=True,capture_output=True)
    if check and p.returncode:
        raise RuntimeError('Database operation failed; inspect the selected application and engine')
    return p


def environment(container):
    c=json.loads(command(['docker','inspect',container]).stdout)[0]
    return dict(x.split('=',1) for x in c['Config'].get('Env',[]) if '=' in x)


def literal(value):
    return "'"+str(value).replace("'","''")+"'"


def ident(value):
    return '"'+str(value).replace('"','""')+'"'


def pg(sql, database='postgres', *, username=None, password=None, tcp=False, check=True):
    env=environment('postgres-db')
    user=username or env.get('POSTGRES_USER','postgres')
    args=['docker','exec','-i','--user','postgres','-e','PGPASSWORD='+str(password or env.get('POSTGRES_PASSWORD','')),
          'postgres-db','psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U',user,'-d',database]
    if tcp:args+=['-h','127.0.0.1']
    return command(args,sql,check=check)


def mysql(sql, *, username='root', password=None, check=True):
    env=environment('mysql-db')
    password=password if password is not None else env.get('MYSQL_ROOT_PASSWORD',env.get('MARIADB_ROOT_PASSWORD',''))
    args=['docker','exec','-i','-e','MYSQL_PWD='+str(password),'mysql-db','sh','-c',
          'exec "$(command -v mysql || command -v mariadb)" -N -B -u "$1"','sh',username]
    return command(args,"SET SESSION sql_mode=CONCAT_WS(',',@@sql_mode,'NO_BACKSLASH_ESCAPES');\n"+sql,check=check)


def read_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {'databases':{},'applications':{}}


def save_state(state):
    STATE.parent.mkdir(mode=0o750,parents=True,exist_ok=True)
    temp=STATE.with_suffix('.tmp')
    temp.write_text(json.dumps(state,indent=2))
    temp.chmod(0o640)
    temp.replace(STATE)


def provision(apps):
    state=read_state()
    changes=[]
    for app in apps:
        for engine, databases in app.get('databases',{}).items():
            for database in databases:
                if database in ('postgres','template0','template1','mysql','sys','information_schema','performance_schema'):
                    raise ValueError('An application cannot own a system database')
                claim=state['databases'].get(engine+':'+database)
                if claim and claim['app'] != app['name']:
                    raise ValueError('Database is already owned by another application')
                users=[u for u in app.get('database_users',[]) if u['database']==database]
                if not users:raise ValueError('Application database requires a restricted account: '+app['name'])
                for user in users:
                    username=user['username'];password=user['password']
                    admin=environment('postgres-db').get('POSTGRES_USER','postgres') if engine=='postgres' else 'root'
                    if not username or username in ('root','postgres',admin):
                        raise ValueError('Refusing application use of an administrator account: '+app['name'])
                    if engine=='postgres':
                        exists=pg('SELECT 1 FROM pg_database WHERE datname='+literal(database)).stdout.strip()=='1'
                        role=pg('SELECT rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication FROM pg_roles WHERE rolname='+literal(username)).stdout.strip()
                        if role=='t':raise ValueError('Existing application role has administrator privileges')
                        if not role:
                            pg('CREATE ROLE '+ident(username)+' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '+literal(password))
                            changes.append(app['name']+':role')
                        if not exists:
                            pg('CREATE DATABASE '+ident(database)+' OWNER '+ident(username))
                            changes.append(app['name']+':database')
                        if pg('SELECT 1',database,username=username,password=password,tcp=True,check=False).returncode:
                            pg('ALTER ROLE '+ident(username)+' PASSWORD '+literal(password))
                            changes.append(app['name']+':credential')
                        pg('ALTER DATABASE '+ident(database)+' OWNER TO '+ident(username)+'; REVOKE CONNECT,TEMPORARY ON DATABASE '+ident(database)+' FROM PUBLIC; GRANT CONNECT,TEMPORARY ON DATABASE '+ident(database)+' TO '+ident(username))
                        pg('ALTER SCHEMA public OWNER TO '+ident(username)+'; GRANT ALL ON SCHEMA public TO '+ident(username)+'; GRANT ALL ON ALL TABLES IN SCHEMA public TO '+ident(username)+'; GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO '+ident(username),database)
                    elif engine=='mysql':
                        quoted='`'+database.replace('`','``')+'`'
                        exists=mysql('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='+literal(database)).stdout.strip()
                        mysql('CREATE DATABASE IF NOT EXISTS '+quoted+' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER IF NOT EXISTS '+literal(username)+"@'%' IDENTIFIED BY "+literal(password))
                        if not exists:changes.append(app['name']+':database')
                        if mysql('SELECT 1',username=username,password=password,check=False).returncode:
                            mysql('ALTER USER '+literal(username)+"@'%' IDENTIFIED BY "+literal(password))
                            changes.append(app['name']+':credential')
                        mysql('GRANT ALL PRIVILEGES ON '+quoted+'.* TO '+literal(username)+"@'%'")
                    else:raise ValueError('Unsupported database engine')
                state['databases'][engine+':'+database]={'group':app['group'],'app':app['name']}
    save_state(state)
    return {'changed':changes}


if __name__=='__main__':
    try:print(json.dumps(provision(json.load(sys.stdin)['applications'])))
    except (ValueError,RuntimeError,KeyError) as exc:
        print(str(exc),file=sys.stderr);sys.exit(1)
