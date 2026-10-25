import unittest
from unittest import mock

from scripts import smoke


class SmokeTests(unittest.TestCase):
    def test_common_http_checks_include_new_catalog_services(self):
        check = smoke.DeployedServices("test_http_errors")
        check.urls = {
            name: f"http://{name}.lambda-url.eu-central-1.localhost.localstack.cloud:4566/"
            for name in ("length", "json-validator", "uppercase")
        }
        responses = [{"error": "method_not_allowed"}, {"error": "body_too_large"}]
        with mock.patch.object(check, "invoke", side_effect=responses * len(check.urls)) as invoke:
            check.test_http_errors()

        self.assertCountEqual(
            [(call.args[0], call.args[2]) for call in invoke.call_args_list],
            [(name, status) for name in check.urls for status in (405, 413)],
        )


if __name__ == "__main__":
    unittest.main()
