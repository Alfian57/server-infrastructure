#!/usr/bin/env python3
"""Trigger workflows for an explicit group/application, never implicitly for every repository."""
import argparse
import subprocess

from catalog import ROOT, catalog, read, select


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--group',default='')
    p.add_argument('--app',default='')
    p.add_argument('--all',action='store_true')
    p.add_argument('--dry-run',action='store_true')
    a=p.parse_args()
    if a.all and (a.group or a.app):p.error('--all cannot be combined with another selector')
    if not(a.group or a.app or a.all):p.error('Select --group, --app, or --all')
    apps=select(a.group,a.app,enabled_only=True,default_only=True)
    data=catalog(a.group,a.app)
    owner=read(ROOT/'platform/vars.yml')['github_username']
    seen=set()
    for item in apps+[m for m in data['mobile_repositories'] if m.get('enabled',True)]:
        repo=item.get('repo_owner',owner)+'/'+item.get('repo',item['name'])
        build=item.get('build',{})
        workflow=build.get('workflow','build-and-deploy.yml')
        ref=build.get('ref','main')
        key=(repo,workflow,ref)
        if key in seen:continue
        seen.add(key)
        print(f'{repo}: {workflow} ref={ref}',flush=True)
        if not a.dry_run:subprocess.run(['gh','workflow','run',workflow,'--repo',repo,'--ref',ref],check=True)


if __name__=='__main__':main()
