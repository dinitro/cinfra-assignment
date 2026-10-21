"""Shared HTTP adapter for Lambda Function URL events.

The platform module copies this file into every service ZIP, so a service only
implements operation(text) -> dict and gets consistent errors, limits and logs.
"""

import base64
import json
import os
import time
import traceback

# Limit on decoded UTF-8 bytes; AWS itself accepts much larger Function URL payloads.
MAX_BODY_BYTES = 64 * 1024


# Raise from an operation to return a specific client error, e.g. HTTPError(422, "json_too_deep").
class HTTPError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status = status
        self.code = code


def text_body(event):
    body = event.get("body")
    if body is None:
        body = ""
    if not isinstance(body, str):
        raise HTTPError(400, "invalid_utf8_body")
    # Function URLs base64-encode bodies whose content type isn't text, e.g. application/octet-stream.
    encoded = event.get("isBase64Encoded", False)
    # Reject oversized bodies before decoding; base64 text is about 4/3 the size of the bytes.
    limit = 4 * ((MAX_BODY_BYTES + 2) // 3) if encoded else MAX_BODY_BYTES
    if len(body) > limit:
        raise HTTPError(413, "body_too_large")
    try:
        raw = base64.b64decode(body, validate=True) if encoded else body.encode("utf-8")
        if len(raw) > MAX_BODY_BYTES:
            raise HTTPError(413, "body_too_large")
        return raw.decode("utf-8")
    except ValueError:
        # Covers bad base64, invalid UTF-8 and lone surrogates.
        raise HTTPError(400, "invalid_utf8_body") from None


def handle(event, context, operation):
    started = time.perf_counter()
    request_id = getattr(context, "aws_request_id", "unknown")
    headers = {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
        "x-request-id": request_id,
    }
    record = {}
    try:
        # Function URL events use payload format 2.0, which puts the method under requestContext.http.
        if event.get("requestContext", {}).get("http", {}).get("method") != "POST":
            raise HTTPError(405, "method_not_allowed")
        body = json.dumps(operation(text_body(event)))
        status = 200
    except HTTPError as error:
        status = error.status
        body = json.dumps({"error": error.code})
    except Exception as error:
        status = 500
        body = json.dumps({"error": "internal_error"})
        # Exception messages and source lines can contain input; log locations only.
        record["error_type"] = type(error).__name__
        record["stack"] = [
            f"{frame.filename}:{frame.lineno}:{frame.name}"
            for frame in traceback.extract_tb(error.__traceback__)
        ]
    if status == 405:
        headers["allow"] = "POST"
    record.update({
        "request_id": request_id,
        "service": os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "local"),
        "status": status,
        "outcome": "server_error" if status >= 500 else "client_error" if status >= 400 else "ok",
        "duration_ms": round((time.perf_counter() - started) * 1000, 3),
    })
    # One JSON line per request; Lambda sends stdout to CloudWatch Logs. Never add the request body.
    print(json.dumps(record))
    return {"statusCode": status, "headers": headers, "body": body}
