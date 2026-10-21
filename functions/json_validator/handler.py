import json

# platform_http is added to the ZIP by the platform module (infra/modules/lambda-service/runtime).
from platform_http import HTTPError, handle


class NonstandardConstant(ValueError):
    pass


# Python's json module accepts NaN and Infinity by default; standard JSON does not.
def reject_constant(name):
    raise NonstandardConstant(name)


def validate(text):
    try:
        # Validate number syntax without overflowing or limiting integer precision.
        json.loads(text, parse_constant=reject_constant, parse_int=str, parse_float=str)
        return {"valid": True}
    except json.JSONDecodeError as error:
        # Parser messages describe the position, never the input itself.
        return {"valid": False, "reason": error.msg, "line": error.lineno, "column": error.colno}
    except NonstandardConstant as error:
        return {"valid": False, "reason": f"{error} is not allowed in JSON"}
    except RecursionError:
        # Extremely deep nesting exhausts the parser: a processing limit, not proof the JSON is invalid.
        raise HTTPError(422, "json_too_deep") from None


def handler(event, context):
    return handle(event, context, validate)
