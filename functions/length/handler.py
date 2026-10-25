# platform_http is added to the ZIP by the platform module (infra/modules/lambda-service/runtime).
from platform_http import handle


def handler(event, context):
    # len() counts Unicode code points: "é🐈" is 2, not its 6 UTF-8 bytes.
    return handle(event, context, lambda text: {"length": len(text)})
