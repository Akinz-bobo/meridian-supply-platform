"""Tests for the sample service. Run with: make service-test"""
import json
import pathlib
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import app  # noqa: E402


class Identity(unittest.TestCase):
    def test_reports_no_identity_outside_a_platform(self):
        self.assertEqual(app.identity(environ={}), {"source": "none", "role": None, "credentials": False})

    def test_reports_static_keys_for_what_they_are_and_does_not_return_them(self):
        result = app.identity(environ={"AWS_ACCESS_KEY_ID": "AKIAEXAMPLE", "AWS_SECRET_ACCESS_KEY": "secret-value"})
        self.assertEqual(result, {"source": "environment-variables", "role": None, "credentials": True})
        self.assertNotIn("AKIAEXAMPLE", json.dumps(result))

    def test_prefers_the_platform_endpoint_to_static_keys(self):
        environ = {app.ECS_CREDENTIALS: "/v2/credentials/abc", "AWS_ACCESS_KEY_ID": "AKIAEXAMPLE"}
        result = app.identity(environ=environ, fetch=lambda url, headers: {"RoleArn": "arn:aws:iam::1:role/r", "AccessKeyId": "x"})
        self.assertEqual(result["source"], "ecs-task-role")

    def test_reports_the_ecs_task_role(self):
        seen = {}

        def fetch(url, headers):
            seen["url"] = url
            return {"RoleArn": "arn:aws:iam::111111111111:role/meridian-dev-sample-task-role", "AccessKeyId": "x", "SecretAccessKey": "y", "Token": "z"}

        result = app.identity(environ={app.ECS_CREDENTIALS: "/v2/credentials/abc"}, fetch=fetch)
        self.assertEqual(seen["url"], "http://169.254.170.2/v2/credentials/abc")
        self.assertEqual(result["source"], "ecs-task-role")
        self.assertEqual(result["role"], "arn:aws:iam::111111111111:role/meridian-dev-sample-task-role")
        self.assertTrue(result["credentials"])

    def test_reports_pod_identity_with_the_role_the_chart_gave(self):
        environ = {app.POD_CREDENTIALS: "http://169.254.170.23/v1/credentials", "ROLE_ARN": "arn:aws:iam::111111111111:role/meridian-dev-sample-pod-role"}
        result = app.identity(environ=environ, fetch=lambda url, headers: {"AccessKeyId": "x"})
        self.assertEqual(result["source"], "eks-pod-identity")
        self.assertEqual(result["role"], "arn:aws:iam::111111111111:role/meridian-dev-sample-pod-role")

    def test_never_returns_a_key_a_secret_or_a_token(self):
        document = {"RoleArn": "arn:aws:iam::1:role/r", "AccessKeyId": "AKIAEXAMPLE", "SecretAccessKey": "secret-value", "Token": "token-value"}
        result = app.identity(environ={app.ECS_CREDENTIALS: "/v2/credentials/abc"}, fetch=lambda url, headers: document)
        rendered = json.dumps(result)
        for forbidden in ("AKIAEXAMPLE", "secret-value", "token-value"):
            self.assertNotIn(forbidden, rendered)
        self.assertEqual(set(result), {"source", "role", "credentials"})

    def test_says_so_when_the_credentials_endpoint_does_not_answer(self):
        def fetch(url, headers):
            raise urllib.error.URLError("unreachable")

        result = app.identity(environ={app.ECS_CREDENTIALS: "/v2/credentials/abc"}, fetch=fetch)
        self.assertEqual(result, {"source": "ecs-task-role", "role": None, "credentials": False})


class Http(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=5) as response:
                return response.status, json.load(response), response.headers
        except urllib.error.HTTPError as error:
            return error.code, json.load(error), error.headers

    def test_health_check_answers(self):
        status, body, _ = self.get("/healthz")
        self.assertEqual((status, body), (200, {"status": "ok"}))

    def test_describes_itself(self):
        status, body, _ = self.get("/")
        self.assertEqual(status, 200)
        self.assertEqual(set(body), {"service", "environment", "platform", "version"})

    def test_answers_under_its_own_path_prefix(self):
        # The load balancer routes /sample/* to the service without
        # rewriting the path.
        self.assertEqual(self.get("/sample/healthz")[0], 200)
        self.assertEqual(self.get("/sample")[0], 200)
        self.assertEqual(self.get("/sample/")[0], 200)

    def test_unknown_paths_are_not_found(self):
        self.assertEqual(self.get("/admin")[0], 404)
        self.assertEqual(self.get("/samplesomething")[0], 404)

    def test_does_not_say_what_it_is_built_with(self):
        _, _, headers = self.get("/")
        self.assertNotIn("Python", headers.get("Server", ""))

    def test_responses_are_not_cached(self):
        _, _, headers = self.get("/identity")
        self.assertEqual(headers.get("Cache-Control"), "no-store")


if __name__ == "__main__":
    unittest.main()
