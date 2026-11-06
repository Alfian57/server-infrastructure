#!/usr/bin/env python3
"""Provision selected databases only; credentials are read on stdin and never logged."""
import json
from pathlib import Path
import re
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


SYSTEM_DATABASES={'postgres','template0','template1','mysql','sys','information_schema','performance_schema'}


def validate_database(engine,database):
    if engine not in ('postgres','mysql'):
        raise ValueError('Unsupported database engine in reset target')
    if not isinstance(database,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,63}',database):
        raise ValueError('Invalid database identifier in reset target')
    if database.lower() in SYSTEM_DATABASES:
        raise ValueError('System database reset is prohibited')


def database_exists(engine,database):
    if engine=='postgres':
        return pg('SELECT 1 FROM pg_database WHERE datname='+literal(database)).stdout.strip()=='1'
    return mysql('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='+literal(database)).stdout.strip()==database


def active_sessions(engine,database):
    if engine=='postgres':
        sql='SELECT count(*) FROM pg_stat_activity WHERE datname='+literal(database)+' AND pid<>pg_backend_pid()'
        return int(pg(sql).stdout.strip() or '0')
    sql='SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE DB='+literal(database)+' AND ID<>CONNECTION_ID()'
    return int(mysql(sql).stdout.strip() or '0')


def preflight_reset(app):
    if app.get('production') is not False:
        raise ValueError('Database reset is allowed only when production is false')
    if not app.get('enabled',True):
        raise ValueError('Database reset is limited to enabled applications')
    name=app.get('name','')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*',name):
        raise ValueError('Invalid application identifier')
    declared=app.get('databases')
    if not isinstance(declared,dict) or not declared:
        raise ValueError('Application has no declared databases')
    state=read_state();desired=[]
    users=app.get('database_users',[]) or []
    for engine,names in declared.items():
        if not isinstance(names,list) or not names:
            raise ValueError('Database declarations must contain at least one database')
        for database in names:
            validate_database(engine,database)
            claim=state.get('databases',{}).get(engine+':'+database)
            if claim and claim.get('app')!=name:
                raise ValueError('Target database is owned by another application')
            matching=[user for user in users if user.get('database')==database]
            if not matching:
                raise ValueError('Every reset target requires a restricted application database user')
            admin=(environment('postgres-db').get('POSTGRES_USER','postgres') if engine=='postgres' else 'root')
            for user in matching:
                username=user.get('username','')
                if not username or username in ('root','postgres','mysql',admin):
                    raise ValueError('Application database user cannot be an administrator')
                if not user.get('password'):
                    raise ValueError('Every reset target requires its application database credential')
            desired.append((engine,database))
    if len(desired)!=len(set(desired)):
        raise ValueError('Duplicate database targets are not allowed')

    owned=[]
    for key,claim in state.get('databases',{}).items():
        if claim.get('app')!=name:continue
        engine,database=key.split(':',1)
        validate_database(engine,database)
        owned.append((engine,database))
    for engine,database in desired:
        claim=state.get('databases',{}).get(engine+':'+database)
        exists=database_exists(engine,database)
        if exists and not claim:
            raise ValueError('Existing target database has no verified application owner')
    # Verify every previously owned database is reachable before any container
    # is stopped or database is dropped. A missing database is safe to forget.
    exists_by_key={}
    for engine,database in owned:
        exists_by_key[engine+':'+database]=database_exists(engine,database)
    return {'application':name,'owned':owned,'exists':exists_by_key}


def reset_application(app):
    """Preflight a single app's databases, then drop only its exclusive claims."""
    plan=preflight_reset(app)
    state=read_state()
    for engine,database in plan['owned']:
        key=engine+':'+database
        claim=state.get('databases',{}).get(key)
        if not claim or claim.get('app')!=plan['application']:
            raise ValueError('Database ownership changed during reset preflight')
    removed=[]
    for engine,database in plan['owned']:
        key=engine+':'+database
        if plan['exists'][key]:
            sessions=active_sessions(engine,database)
            if sessions:
                raise ValueError('Database still has active connections; refusing reset')
            if engine=='postgres':
                pg('DROP DATABASE '+ident(database))
            else:
                mysql('DROP DATABASE `'+database.replace('`','``')+'`')
            removed.append({'engine':engine,'database':database})
        state['databases'].pop(key,None)
        save_state(state)
    return {'application':plan['application'],'removed_databases':removed}


def provision(apps):
    state=read_state()
    changes=[];pending=[]
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
                initialized=bool(exists) and (claim or {}).get('initialized',True)
                if not initialized:pending.append(app['name'])
                state['databases'][engine+':'+database]={'group':app['group'],'app':app['name'],'initialized':initialized}
    save_state(state)
    return {'changed':changes,'needs_initialization':sorted(set(pending))}


if __name__=='__main__':
    try:
        payload=json.load(sys.stdin)
        operation=payload.get('operation','provision')
        if operation=='validate-reset':result=preflight_reset(payload['application'])
        elif operation=='reset':result=reset_application(payload['application'])
        elif operation=='provision':result=provision(payload['applications'])
        else:raise ValueError('Unsupported database operation')
        print(json.dumps(result))
    except (ValueError,RuntimeError,KeyError) as exc:
        print(str(exc),file=sys.stderr);sys.exit(1)
