"""Exercise deployed LocalStack Function URLs, supplied as Terraform JSON on stdin."""

import json
import sys
import unittest
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener


class DeployedServices(unittest.TestCase):
    urls = {}
    opener = build_opener(ProxyHandler({}))

    # Refuse anything that isn't a LocalStack URL so these tests can never hit real AWS.
    @classmethod
    def setUpClass(cls):
        for name in cls.urls:
            url = urlsplit(cls.urls[name])
            if url.scheme != "http" or url.port != 4566 or not url.hostname.endswith(".localhost.localstack.cloud"):
                raise ValueError("Smoke tests only accept local Function URLs, never real AWS endpoints")

    def invoke(self, name, body, status=200, method="POST", content_type="text/plain; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        url = urlsplit(self.urls[name])
        # Preserve URL routing without relying on public wildcard DNS or host proxy settings.
        request = Request(url._replace(netloc="127.0.0.1:4566").geturl(), data=data, method=method,
                          headers={"Host": url.netloc, "Content-Type": content_type})
        try:
            response = self.opener.open(request, timeout=90)
        except HTTPError as error:
            response = error
        with response:
            payload = response.read()
            self.assertEqual(response.status, status, payload)
            self.assertTrue(response.headers.get("content-type", "").startswith("application/json"))
            self.assertTrue(response.headers.get("x-request-id"))
            self.assertEqual(response.headers.get("cache-control"), "no-store")
            if status == 405:
                self.assertEqual(response.headers.get("allow"), "POST")
            return json.loads(payload)

    def test_services(self):
        self.assertEqual(self.invoke("length", "hello"), {"length": 5})
        self.assertEqual(self.invoke("json-validator", '{"a":1}'), {"valid": True})
        self.assertEqual(self.invoke("json-validator", '{"a":}'), {"valid": False, "reason": "Expecting value", "line": 1, "column": 6})
        # The deepest nesting that fits the body limit must still parse on the deployed runtime.
        self.assertEqual(self.invoke("json-validator", "[" * 32767 + "]" * 32767), {"valid": True})

    def test_binary_transport(self):
        self.assertEqual(self.invoke("length", "é🐈", content_type="application/octet-stream"), {"length": 2})
        self.assertEqual(self.invoke("json-validator", '{"cat":"🐈"}', content_type="application/octet-stream"), {"valid": True})

    def test_http_errors(self):
        for name in self.urls:
            with self.subTest(service=name):
                self.assertEqual(self.invoke(name, "", 405, method="GET"), {"error": "method_not_allowed"})
                self.assertEqual(self.invoke(name, "a" * 65537, 413), {"error": "body_too_large"})


if __name__ == "__main__":
    DeployedServices.urls = json.load(sys.stdin)
    unittest.main(verbosity=2)
