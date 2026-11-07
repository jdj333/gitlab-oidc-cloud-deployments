"""Evaluate the actual Terraform-rendered predicates; not a JWT signature validator.

The small CEL interpreter supports only the equality conjunction emitted by this
repo. Unsupported expressions fail loudly so widening a policy cannot pass by
being silently ignored. Live cloud authorization is tested separately.
"""
import copy
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRUST = json.loads((ROOT / '.test-output/trust.json').read_text())['trust']['value']
AUDIENCES = {'aws': 'sts.amazonaws.com', 'azure': 'api://AzureADTokenExchange', 'gcp': 'https://gitlab.com'}


def cel_matches(expression, claims):
    terms = expression.split(' && ')
    matches = [re.fullmatch(r"assertion\.([a-z_]+) == '([^']*)'", term) for term in terms]
    if not all(matches):
        raise ValueError('Unsupported CEL expression; extend tests before changing policy syntax.')
    return all(claims.get(m[1]) == m[2] for m in matches)


def permits(cloud, env, claims):
    # Signature, time, discovery and JWKS validation are the cloud provider's job.
    if claims.get('iss') != TRUST['issuer']:
        return False
    audience = claims.get('aud', [])
    audiences = audience if isinstance(audience, list) else [audience]
    if cloud == 'aws':
        conditions = TRUST['aws_conditions'][env]
        if set(conditions) != {'StringEquals'}:
            raise ValueError('Unexpected AWS policy operator')
        return all(
            expected in audiences if key == 'gitlab.com:aud' else claims.get(key.split(':', 1)[1]) == expected
            for key, expected in conditions['StringEquals'].items()
        )
    if cloud == 'azure':
        fic = TRUST['azure_federation'][env]
        return claims.get('iss') == fic['issuer'] and claims.get('sub') == fic['subject'] and bool(set(audiences) & set(fic['audience']))
    if cloud == 'gcp':
        return TRUST['gcp_audience'] in audiences and cel_matches(TRUST['gcp_conditions'][env], claims)
    raise ValueError(cloud)


def valid_claims(cloud, env):
    branch = {'dev': 'develop', 'prod': 'main'}[env]
    return {
        'iss': 'https://gitlab.com', 'aud': AUDIENCES[cloud],
        'sub': f'project_path:example-platform/gitlab-oidc-cloud-deployments:ref_type:branch:ref:{branch}',
        'project_id': '12345678', 'namespace_id': '123456',
        'ref_protected': 'true', 'pipeline_source': 'push',
    }


class TrustTests(unittest.TestCase):
    def test_cel_unknown_syntax_fails_loudly(self):
        with self.assertRaises(ValueError):
            cel_matches("true || assertion.project_id == '12345678'", {})

    def test_azure_additional_claims_are_not_cloud_enforced(self):
        # Documents the real limitation rather than inventing a stronger Azure policy.
        for env in ('dev', 'prod'):
            claims = valid_claims('azure', env)
            claims.update(project_id='999', ref_protected='false', pipeline_source='schedule')
            self.assertTrue(permits('azure', env, claims))


def case(cloud, env, mutation, allowed):
    def test(self):
        claims = valid_claims(cloud, env)
        for key, value in mutation.items():
            if value is None:
                claims.pop(key, None)
            else:
                claims[key] = value
        self.assertEqual(permits(cloud, env, claims), allowed)
    return test


for cloud in AUDIENCES:
    for env in ('dev', 'prod'):
        base = valid_claims(cloud, env)['sub']
        scenarios = {
            'allowed_branch': ({}, True),
            'feature_branch': ({'sub': base.rsplit(':', 1)[0] + ':feature/steal-prod'}, False),
            'other_environment_branch': ({'sub': base.rsplit(':', 1)[0] + (':main' if env == 'dev' else ':develop')}, False),
            'tag_named_like_branch': ({'sub': base.replace('ref_type:branch', 'ref_type:tag')}, False),
            'fork': ({'sub': base.replace('example-platform/', 'attacker/')}, False),
            'different_project': ({'sub': base.replace('gitlab-oidc-cloud-deployments', 'another-project')}, False),
            'wrong_audience': ({'aud': 'https://attacker.invalid'}, False),
            'wrong_issuer': ({'iss': 'https://gitlab.attacker.invalid'}, False),
            'missing_subject': ({'sub': None}, False),
            'missing_audience': ({'aud': None}, False),
            'missing_issuer': ({'iss': None}, False),
        }
        if cloud in ('aws', 'gcp'):
            scenarios.update({
                'recreated_project': ({'project_id': '999999'}, False),
                'moved_namespace': ({'namespace_id': '999999'}, False),
                'unprotected_branch': ({'ref_protected': 'false'}, False),
                'missing_protection': ({'ref_protected': None}, False),
                'merge_request_pipeline': ({'pipeline_source': 'merge_request_event'}, False),
                'scheduled_pipeline': ({'pipeline_source': 'schedule'}, False),
                'web_pipeline': ({'pipeline_source': 'web'}, False),
            })
        for name, (mutation, allowed) in scenarios.items():
            setattr(TrustTests, f'test_{cloud}_{env}_{name}', case(cloud, env, mutation, allowed))
