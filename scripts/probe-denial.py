#!/usr/bin/env python3
"""Opt-in real token-exchange rejection check. Never performs a deployment.

An expected authorization error passes. HTTP/network/configuration errors fail.
A successful exchange fails and the credentials are discarded without logging.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


def required(key):
    value = os.environ.get(key)
    if not value:
        raise ValueError(f'Missing variable: {key}')
    return value


def expected_denial(cloud, status, body):
    if cloud == 'aws':
        root = ET.fromstring(body)
        fields = {node.tag.rsplit('}', 1)[-1]: node.text for node in root.iter()}
        return status == 403 and fields.get('Code') == 'AccessDenied' and 'AssumeRoleWithWebIdentity' in fields.get('Message', '')
    data = json.loads(body)
    if cloud == 'azure':
        return status in (400, 401) and 'AADSTS700213' in data.get('error_description', '')
    if cloud == 'gcp':
        return status == 400 and data.get('error') in ('invalid_grant', 'unauthorized_client') and 'rejected by the attribute condition' in data.get('error_description', '')
    raise ValueError('Unknown cloud')


def main():
    if os.environ.get('CI_COMMIT_BRANCH') != 'oidc-deny-probe' or os.environ.get('CI_PIPELINE_SOURCE') != 'push':
        raise ValueError('Run only from a push pipeline on oidc-deny-probe.')
    if os.environ.get('CI_DEBUG_TRACE') == 'true':
        raise ValueError('Debug tracing is forbidden.')
    cloud = sys.argv[1]
    token = required('GITLAB_OIDC_TOKEN')
    if cloud == 'aws':
        url = 'https://sts.amazonaws.com/'
        fields = {'Action': 'AssumeRoleWithWebIdentity', 'Version': '2011-06-15',
                  'RoleArn': required('PROBE_AWS_ROLE_ARN'), 'RoleSessionName': 'gitlab-deny-probe',
                  'WebIdentityToken': token, 'DurationSeconds': '900'}
    elif cloud == 'azure':
        tenant = required('PROBE_AZURE_TENANT_ID')
        import uuid
        uuid.UUID(tenant)  # Never allow a variable to redirect the assertion to another host.
        url = f'https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token'
        fields = {'client_id': required('PROBE_AZURE_CLIENT_ID'), 'scope': 'https://storage.azure.com/.default',
                  'grant_type': 'client_credentials', 'client_assertion_type': 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
                  'client_assertion': token}
    elif cloud == 'gcp':
        url = 'https://sts.googleapis.com/v1/token'
        fields = {'audience': '//iam.googleapis.com/' + required('PROBE_GCP_WORKLOAD_PROVIDER'),
                  'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
                  'requested_token_type': 'urn:ietf:params:oauth:token-type:access_token',
                  'scope': 'https://www.googleapis.com/auth/cloud-platform',
                  'subject_token_type': 'urn:ietf:params:oauth:token-type:jwt', 'subject_token': token}
    else:
        raise ValueError('Choose aws, azure, or gcp')
    request = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(), method='POST')
    # Do not follow redirects with an assertion-bearing request.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            response.read()  # Discard successful credentials; no token or response body is logged.
        print('FAIL: Unauthorized branch received credentials.', file=sys.stderr)
        return 1
    except urllib.error.HTTPError as error:
        try:
            denied = expected_denial(cloud, error.code, error.read().decode())
        except (ValueError, ET.ParseError):
            denied = False
        if denied:
            print(f'PASS: {cloud} rejected the unauthorized GitLab identity.')
            return 0
        print(f'FAIL: HTTP {error.code} was not the expected policy denial; check configuration securely.', file=sys.stderr)
        return 1
    except urllib.error.URLError:
        print('FAIL: Token endpoint could not be reached; no denial was proven.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, IndexError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
