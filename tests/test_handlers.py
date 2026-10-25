import base64
import contextlib
import io
import json
import sys
import unittest
from unittest import mock
from pathlib import Path
from types import SimpleNamespace

# platform_http is only added at packaging time; make it importable for local tests.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "infra/modules/lambda-service/runtime"))

from functions.length.handler import handler as length
from functions.json_validator.handler import handler as validate_json
import functions.json_validator.handler as json_validator_module
from platform_http import handle


class HandlerTests(unittest.TestCase):
    # Call a handler with a minimal Function URL (payload 2.0) event and capture its log line.
    def invoke(self, handler, body, method="POST", encoded=False):
        event = {
            "requestContext": {"http": {"method": method}},
            "body": body,
            "isBase64Encoded": encoded,
        }
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            response = handler(event, SimpleNamespace(aws_request_id="test-request"))
        self.log = output.getvalue()
        return response

    def test_counts_characters(self):
        response = self.invoke(length, "hello")
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), {"length": 5})

    def test_invalid_json_is_a_successful_validation_with_a_location(self):
        response = self.invoke(validate_json, '{"a":}')
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), {"valid": False, "reason": "Expecting value", "line": 1, "column": 6})

    def test_invalid_reasons_never_echo_input(self):
        secret = "sensitive-request-do-not-echo"
        for text, reason in [('{"%s":' % secret, "Expecting value"), ('{"a":NaN}', "NaN is not allowed in JSON"), ("", "Expecting value")]:
            with self.subTest(text=text):
                body = json.loads(self.invoke(validate_json, text)["body"])
                self.assertEqual(body["reason"], reason)
                self.assertNotIn(secret, json.dumps(body))

    def test_only_post_is_supported(self):
        for handler in (length, validate_json):
            with self.subTest(handler=handler.__module__):
                response = self.invoke(handler, "hello", method="GET")
                self.assertEqual(response["statusCode"], 405)
                self.assertEqual(response["headers"]["allow"], "POST")
                self.assertEqual(json.loads(response["body"]), {"error": "method_not_allowed"})

    def test_length_counts_unicode_code_points_and_empty_text(self):
        for text, count in [("", 0), (None, 0), ("é🐈", 2), ("e\u0301", 2), ("🇳🇱", 2)]:
            with self.subTest(text=text):
                response = self.invoke(length, text)
                self.assertEqual(response["statusCode"], 200)
                self.assertEqual(json.loads(response["body"]), {"length": count})

    def test_base64_encoded_utf8_is_decoded_for_both_services(self):
        for handler, text, expected in [
            (length, "é🐈", {"length": 2}),
            (validate_json, '{"cat":"🐈"}', {"valid": True}),
        ]:
            with self.subTest(handler=handler.__module__):
                body = base64.b64encode(text.encode("utf-8")).decode("ascii")
                response = self.invoke(handler, body, encoded=True)
                self.assertEqual(response["statusCode"], 200)
                self.assertEqual(json.loads(response["body"]), expected)

    def test_bad_encoding_is_a_client_error(self):
        for handler in (length, validate_json):
            for body, encoded in [("not base64!", True), ("/w==", True), ("🐈", True), (123, False), ("\ud800", False)]:
                with self.subTest(handler=handler.__module__, body=repr(body)):
                    response = self.invoke(handler, body, encoded=encoded)
                    self.assertEqual(response["statusCode"], 400)
                    self.assertEqual(json.loads(response["body"]), {"error": "invalid_utf8_body"})

    def test_body_limit_is_measured_in_decoded_bytes(self):
        text = "é" * 32768
        response = self.invoke(length, text)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), {"length": 32768})
        for handler in (length, validate_json):
            for encoded in (False, True):
                with self.subTest(handler=handler.__module__, encoded=encoded):
                    oversized = text + "a"
                    body = base64.b64encode(oversized.encode()).decode() if encoded else oversized
                    response = self.invoke(handler, body, encoded=encoded)
                    self.assertEqual(response["statusCode"], 413)
                    self.assertEqual(json.loads(response["body"]), {"error": "body_too_large"})

    def test_accepts_json_values_but_not_javascript_extensions(self):
        valid = ['{}', '[]', 'null', 'true', '42', '"hello"', ' \n {"a":[1,false,null]} \t', '1e9999', '9' * 5000]
        invalid = ['', ' ', None, '{', '[1,]', '{"a":1,}', 'true false', 'NaN', 'Infinity', '-Infinity', '{"x":NaN}', '// comment\n{}', '01']
        for expected, inputs in [(True, valid), (False, invalid)]:
            for text in inputs:
                with self.subTest(text=repr(text)[:60]):
                    response = self.invoke(validate_json, text)
                    self.assertEqual(response["statusCode"], 200)
                    self.assertEqual(json.loads(response["body"])["valid"], expected)

    def test_deepest_nesting_within_the_body_limit_is_valid(self):
        depth = 32767  # 65,534 bytes: just under the 64 KiB body limit
        response = self.invoke(validate_json, "[" * depth + "]" * depth)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), {"valid": True})

    def test_parser_capacity_is_not_reported_as_invalid_json(self):
        # Python 3.14 parses any nesting that fits the body limit, so simulate the parser giving up.
        with mock.patch.object(json_validator_module.json, "loads", side_effect=RecursionError):
            response = self.invoke(validate_json, "[[]]")
        self.assertEqual(response["statusCode"], 422)
        self.assertEqual(json.loads(response["body"]), {"error": "json_too_deep"})

    def test_logs_have_correlation_and_outcome_but_never_request_bodies(self):
        secret = "sensitive-request-do-not-log"
        for handler, method, status in [(length, "POST", 200), (validate_json, "POST", 200), (length, "GET", 405)]:
            with self.subTest(handler=handler.__module__, method=method):
                response = self.invoke(handler, secret, method=method)
                record = json.loads(self.log)
                self.assertEqual(record["request_id"], "test-request")
                self.assertEqual(record["status"], status)
                self.assertGreaterEqual(record["duration_ms"], 0)
                self.assertNotIn(secret, self.log)
                self.assertEqual(response["headers"]["x-request-id"], record["request_id"])
                self.assertEqual(response["headers"]["cache-control"], "no-store")

    def test_unexpected_errors_are_redacted_and_observable(self):
        def fail(text):
            raise RuntimeError(text)

        secret = "secret-which-must-not-appear-in-an-exception-log"
        response = self.invoke(lambda event, context: handle(event, context, fail), secret)
        self.assertEqual(response["statusCode"], 500)
        self.assertEqual(json.loads(response["body"]), {"error": "internal_error"})
        record = json.loads(self.log)
        self.assertEqual(record["outcome"], "server_error")
        self.assertEqual(record["error_type"], "RuntimeError")
        self.assertTrue(record["stack"])
        self.assertNotIn(secret, self.log)
        self.assertNotIn(secret, response["body"])


if __name__ == "__main__":
    unittest.main()
