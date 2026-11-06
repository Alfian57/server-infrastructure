import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import catalog


class CatalogTests(unittest.TestCase):
    def test_uty_selection_reads_no_other_group(self):
        with mock.patch.object(catalog,'read',wraps=catalog.read) as reader:
            apps=catalog.select('uty',enabled_only=True)
        self.assertEqual({a['name'] for a in apps},{'sistertika-uty-api','sistertika-uty-web'})
        paths=[str(call.args[0].relative_to(ROOT)) for call in reader.call_args_list]
        self.assertTrue(all(p=='projects/index.yml' or p.startswith('projects/uty/') for p in paths))

    def test_missing_or_mismatched_target_fails_before_deployment(self):
        for group,app in [('', ''),('missing',''),('uty','guardian-lab')]:
            with self.subTest(group=group,app=app),self.assertRaises(ValueError):
                catalog.select(group,app,require_target=True)

    def test_groups_are_independent_of_github_owner(self):
        apps=catalog.select('lomba')
        self.assertEqual({a['name'] for a in apps},{'ruang-tenang-api','ruang-tenang-web','satu-platform','guardian-lab','guardian-lab-ai'})
        self.assertEqual(next(a for a in apps if a['name']=='guardian-lab')['repo_owner'],'DeryWahyu')

    def test_disabled_apps_are_visible_but_not_deployed(self):
        self.assertIn('panca-trivia',{a['name'] for a in catalog.select('personal')})
        self.assertNotIn('panca-trivia',{a['name'] for a in catalog.select('personal',enabled_only=True)})
        with self.assertRaises(ValueError):catalog.select(app='panca-trivia',enabled_only=True)

    def test_staging_router_requires_explicit_selection(self):
        self.assertNotIn('aldera-router-staging',{a['name'] for a in catalog.select('alderatech',enabled_only=True,default_only=True)})
        self.assertEqual(catalog.select(app='aldera-router-staging',enabled_only=True)[0]['name'],'aldera-router-staging')

    def test_domain_aliases_are_not_lost(self):
        api=catalog.select(app='sistertika-uty-api')[0]
        self.assertEqual(set(catalog.domains(api)),{'sistertika-api.alfian-gading.my.id','api.sistertika.com'})

    def test_retired_apps_cannot_be_selected(self):
        for name in ('posyandu','materi-ku','ruang-istirahat','tech-talk','campus-project-hub-api','campus-project-hub-web'):
            with self.subTest(app=name),self.assertRaises(ValueError):catalog.select(app=name)


class LockTests(unittest.TestCase):
    def test_ssh_nonblocking_stderr_does_not_leak_into_ansible(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            fake_ssh=root/'ssh.py'
            fake_ssh.write_text("import os,sys\nos.set_blocking(2,False)\nprint('LOCKED '+'a'*48,flush=True)\nsys.stdin.read()\n")
            ansible=root/'ansible-playbook'
            ansible.write_text('#!'+sys.executable+"\nimport os,sys\nsys.exit(0 if os.get_blocking(2) else 77)\n")
            ansible.chmod(0o750)
            source=("import sys,argparse\nfrom unittest import mock\nsys.path.insert(0,"+repr(str(ROOT/'scripts'))+")\nimport deploy\n"
                    "a=argparse.Namespace(operation='deploy',group='uty',app='',service='',destroy_data=False)\n"
                    "with mock.patch.object(deploy,'inventory_host',return_value={}),mock.patch.object(deploy,'ssh_args',return_value=[sys.executable,"+repr(str(fake_ssh))+"]):\n"
                    " sys.exit(deploy.run(a))\n")
            result=subprocess.run([sys.executable,'-c',source],env={**os.environ,'PATH':str(root)+os.pathsep+os.environ['PATH']},capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stderr)

    def test_two_entrypoints_share_a_lock_and_valid_inheritance_works(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);locks=root/'locks';locks.mkdir()
            script=(ROOT/'roles/common/files/with-deployment-lock.sh').read_text()
            script=script.replace('/opt/docker-stack/.locks',str(locks)).replace('/opt/docker-stack/.registry',str(root/'registry'))
            path=root/'lock.sh';path.write_text(script);path.chmod(0o750)
            owner=subprocess.Popen(['bash',str(path),'--hold'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                line=owner.stdout.readline().strip();self.assertTrue(line.startswith('LOCKED '),line)
                token=line.split()[1]
                blocked=subprocess.run(['bash',str(path),'true'],env={**os.environ,'INFRA_LOCK_TOKEN':'invalid','INFRA_LOCK_TIMEOUT':'0'},capture_output=True,text=True)
                self.assertNotEqual(blocked.returncode,0)
                nested=subprocess.run(['bash',str(path),'printf','nested-ok'],env={**os.environ,'INFRA_LOCK_TOKEN':token},capture_output=True,text=True,timeout=5)
                self.assertEqual(nested.returncode,0,nested.stderr)
                self.assertEqual(nested.stdout,'nested-ok')
            finally:
                owner.stdin.close();owner.wait(timeout=5);owner.stdout.close();owner.stderr.close()
            self.assertFalse((locks/'holder.json').exists())


spec=importlib.util.spec_from_file_location('resources',ROOT/'roles/common/files/manage-resources.py')
resources=importlib.util.module_from_spec(spec);spec.loader.exec_module(resources)


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup)
        self.base=Path(self.directory.name)/'applications';self.base.mkdir()
        self.patch_base=mock.patch.object(resources,'BASE',self.base);self.patch_base.start();self.addCleanup(self.patch_base.stop)
        self.patch_state=mock.patch.object(resources.db,'STATE',Path(self.directory.name)/'state.json');self.patch_state.start();self.addCleanup(self.patch_state.stop)

    def test_retirement_validates_entire_set_before_any_mutation(self):
        payload={'confirm_destroy_data':True,'applications':[{'name':'campus-project-hub-api','databases':{'postgres':['pui']}}],
                 'retained_databases':{'postgres':['pui']},'credentials':{}}
        with mock.patch.object(resources,'PublicResources') as api,mock.patch.object(resources.db,'command') as command:
            with self.assertRaisesRegex(ValueError,'retained application'):resources.decommission(payload)
        api.assert_not_called();command.assert_not_called()

    def test_retirement_rejects_an_active_application(self):
        payload={'confirm_destroy_data':True,'applications':[{'name':'guardian-lab'}]}
        with self.assertRaisesRegex(ValueError,'authorized retirement'):resources.decommission(payload)

    def test_retirement_rejects_symlinked_application_directory(self):
        (self.base/'posyandu').symlink_to(self.base.parent,target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'symlink'):resources.app_directory('posyandu')

    def test_proxy_cleanup_preserves_domains_of_other_apps(self):
        api=object.__new__(resources.PublicResources)
        api.records=mock.Mock(return_value=iter([]))
        api.npm=mock.Mock(side_effect=[[
            {'id':10,'domain_names':['posyandu.alfian-gading.my.id','keep.example.com'],'forward_host':'same','forward_port':80},
            {'id':11,'domain_names':['uty.example.com']}
        ],{},[{'id':10,'certificate_id':1},{'id':11,'certificate_id':2}],[{'id':1,'domain_names':['*.alfian-gading.my.id']} ]])
        api.remove({'name':'posyandu','proxy':{'domain':'posyandu.alfian-gading.my.id'}})
        update=api.npm.call_args_list[1]
        self.assertEqual(update.args[:2],('nginx/proxy-hosts/10','PUT'))
        self.assertEqual(update.args[2]['domain_names'],['keep.example.com'])
        self.assertEqual(len(api.npm.call_args_list),4)

    def test_image_preservation_excludes_other_groups(self):
        (self.base/'sistertika-uty-api').mkdir()
        containers=[{'Name':'/sistertika-uty-api','Image':'sha256:uty','Mounts':[],
                     'Config':{'Labels':{'com.docker.compose.project.working_dir':str(self.base/'sistertika-uty-api'),'com.docker.compose.service':'api'}}},
                    {'Name':'/guardian-lab','Image':'sha256:lomba','Mounts':[],
                     'Config':{'Labels':{'com.docker.compose.project.working_dir':str(self.base/'guardian-lab'),'com.docker.compose.service':'web'}}}]
        with mock.patch.object(resources,'inspect_all',return_value=containers):
            result=resources.preserve_images({'name':'sistertika-uty-api'})
        self.assertTrue(result['preserved'])
        overlay=json.loads((self.base/'sistertika-uty-api/docker-compose.preserve.json').read_text())
        self.assertEqual(overlay,{'services':{'api':{'image':'sha256:uty'}}})

    def test_failed_initialization_remains_pending_on_retry(self):
        state={'databases':{'postgres:router':{'group':'alderatech','app':'router','initialized':False}},'applications':{}}
        resources.db.save_state(state)
        app={'name':'router','group':'alderatech','databases':{'postgres':['router']},
             'database_users':[{'database':'router','username':'router_user','password':'fixture-password'}]}
        def query(sql,*args,**kwargs):
            output='f' if 'rolsuper' in sql else '1'
            return subprocess.CompletedProcess([],0,stdout=output,stderr='')
        with mock.patch.object(resources.db,'environment',return_value={'POSTGRES_USER':'postgres'}),mock.patch.object(resources.db,'pg',side_effect=query):
            result=resources.db.provision([app])
        self.assertEqual(result['needs_initialization'],['router'])
        self.assertNotIn('router:database',result['changed'])

    def test_initialization_marker_does_not_change_other_apps(self):
        resources.db.save_state({'databases':{'postgres:router':{'app':'router','initialized':False},
                                             'postgres:pui':{'app':'pui','initialized':False}},'applications':{}})
        payload=json.dumps({'operation':'initialized','application':{'name':'router'}})
        import io
        with mock.patch.object(sys,'stdin',io.StringIO(payload)):resources.main()
        state=resources.db.read_state()
        self.assertTrue(state['databases']['postgres:router']['initialized'])
        self.assertFalse(state['databases']['postgres:pui']['initialized'])


if __name__=='__main__':unittest.main()
