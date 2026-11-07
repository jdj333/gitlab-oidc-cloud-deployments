import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("probe", Path(__file__).resolve().parents[1] / "scripts/probe-denial.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class ProbeTests(unittest.TestCase):
    def test_aws_authorization_denial(self):
        body = "<ErrorResponse><Error><Code>AccessDenied</Code><Message>Not authorized to perform sts:AssumeRoleWithWebIdentity</Message></Error></ErrorResponse>"
        self.assertTrue(probe.expected_denial("aws", 403, body))
        self.assertFalse(probe.expected_denial("aws", 400, body.replace("AccessDenied", "InvalidIdentityToken")))

    def test_azure_subject_mismatch(self):
        self.assertTrue(probe.expected_denial("azure", 401, json.dumps({"error_description": "AADSTS700213: No matching federated identity record"})))
        for code in ("AADSTS700211", "AADSTS700212", "AADSTS700016"):
            self.assertFalse(probe.expected_denial("azure", 401, json.dumps({"error_description": code})))

    def test_gcp_attribute_denial(self):
        for error in ("unauthorized_client", "invalid_grant"):
            self.assertTrue(probe.expected_denial("gcp", 400, json.dumps({"error": error, "error_description": "The given credential is rejected by the attribute condition."})))
        self.assertFalse(probe.expected_denial("gcp", 400, json.dumps({"error": "invalid_grant", "error_description": "Invalid audience"})))

    def test_server_errors_do_not_prove_denial(self):
        for cloud in ("azure", "gcp"):
            self.assertFalse(probe.expected_denial(cloud, 500, "{}"))
