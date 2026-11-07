import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
CI = yaml.safe_load((ROOT / '.gitlab-ci.yml').read_text())
AUD = {'aws': 'sts.amazonaws.com', 'azure': 'api://AzureADTokenExchange', 'gcp': 'https://gitlab.com'}


def rule_matches(expression, variables):
    # A strict subset matching this repository's explicit rules; no eval().
    checks = []
    for term in expression.split(' && '):
        match = re.fullmatch(r'\$([A-Z_]+) == ("[^"]*"|null)', term)
        if not match:
            raise ValueError(f'Unsupported GitLab rule: {term}')
        target = None if match[2] == 'null' else match[2][1:-1]
        checks.append(variables.get(match[1]) == target)
    return all(checks)


class PipelineTests(unittest.TestCase):
    def test_no_tokens_on_validation_jobs(self):
        for name in ('unit-tests', 'render-trust', 'terraform-checks'):
            self.assertNotIn('id_tokens', CI[name])

    def test_deployments_are_disabled_by_default(self):
        self.assertTrue(all(CI['variables'][f'ENABLE_{c.upper()}_DEPLOY'] == 'false' for c in AUD))

    def test_deployment_gates(self):
        for cloud in AUD:
            for env, branch in [('dev', 'develop'), ('prod', 'main')]:
                with self.subTest(cloud=cloud, env=env):
                    job = CI[f'deploy-{cloud}-{env}']
                    self.assertEqual(job['extends'], '.deploy')
                    self.assertEqual(job['id_tokens']['GITLAB_OIDC_TOKEN']['aud'], AUD[cloud])
                    self.assertEqual(job['environment']['name'], f'{cloud}/{env}')
                    self.assertEqual(job['resource_group'], f'{cloud}-{env}')
                    self.assertEqual(job['rules'][-1], {'when': 'never'})
                    self.assertFalse(job['rules'][0]['allow_failure'])
                    self.assertEqual(job['rules'][0]['when'], 'manual' if env == 'prod' else 'on_success')
                    rule = job['rules'][0]['if']
                    values = {f'ENABLE_{cloud.upper()}_DEPLOY': 'true', 'CI_PIPELINE_SOURCE': 'push',
                              'CI_COMMIT_BRANCH': branch, 'CI_COMMIT_REF_PROTECTED': 'true'}
                    self.assertTrue(rule_matches(rule, values))
                    for mutation in (
                        {'CI_COMMIT_BRANCH': 'feature/unauthorized'}, {'CI_COMMIT_BRANCH': 'oidc-deny-probe'},
                        {'CI_COMMIT_BRANCH': 'develop' if env == 'prod' else 'main'},
                        {'CI_COMMIT_TAG': branch}, {'CI_PIPELINE_SOURCE': 'merge_request_event'},
                        {'CI_PIPELINE_SOURCE': 'schedule'}, {'CI_PIPELINE_SOURCE': 'web'},
                        {'CI_COMMIT_REF_PROTECTED': 'false'}, {f'ENABLE_{cloud.upper()}_DEPLOY': 'false'},
                    ):
                        self.assertFalse(rule_matches(rule, values | mutation), mutation)

    def test_cloud_script_guards_and_cleanup(self):
        base = {'PATH': os.environ['PATH'], 'DEPLOY_ENV': 'prod', 'CI_COMMIT_BRANCH': 'main',
                'CI_COMMIT_SHA': 'a'*40, 'CI_PROJECT_ID': '12345678', 'CI_PIPELINE_ID': '100',
                'CI_JOB_ID': '200', 'CI_COMMIT_REF_PROTECTED': 'true', 'CI_PIPELINE_SOURCE': 'push',
                'GITLAB_OIDC_TOKEN': 'FAKE-TEST-TOKEN'}
        for mutation in ({'CI_COMMIT_BRANCH': 'feature/no'}, {'CI_COMMIT_REF_PROTECTED': 'false'},
                         {'CI_PIPELINE_SOURCE': 'merge_request_event'}, {'CI_COMMIT_TAG': 'main'},
                         {'CI_DEBUG_TRACE': 'true'}, {'AWS_ACCESS_KEY_ID': 'STATIC-TEST-KEY'},
                         {'AZURE_STORAGE_KEY': 'STATIC-TEST-KEY'}, {'GOOGLE_APPLICATION_CREDENTIALS': '/tmp/key'},
                         {'CI_COMMIT_SHA': 'malformed"json'}, {'DEPLOY_ENV': 'qa'}):
            for cloud in AUD:
                with self.subTest(cloud=cloud, mutation=mutation), tempfile.TemporaryDirectory() as temp:
                    # No cloud CLI exists in this test's configuration. A guard must fail first.
                    result = subprocess.run(['bash', f'scripts/deploy-{cloud}.sh'], cwd=ROOT,
                                            env=base | mutation | {'TMPDIR': temp}, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('FAKE-TEST-TOKEN', result.stdout + result.stderr)
                    self.assertNotIn('command not found', result.stderr)
                    self.assertEqual(list(Path(temp).iterdir()), [])
        with tempfile.TemporaryDirectory() as temp:
            # Authorized branch reaches configuration validation, then removes temporary token files.
            result = subprocess.run(['bash', 'scripts/deploy-aws.sh'], cwd=ROOT,
                                    env=base | {'TMPDIR': temp}, capture_output=True, text=True)
            self.assertIn('Missing required variable: AWS_ROLE_ARN', result.stderr)
            self.assertEqual(list(Path(temp).iterdir()), [])
