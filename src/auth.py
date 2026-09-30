import hmac
import os

def is_admin(authorization: str | None) -> bool:
    """Return True only when the caller presents the configured admin bearer token."""
    expected = os.environ.get("ADMIN_TOKEN")
    if not expected or not authorization or not authorization.startswith("Bearer "):
        return False
    supplied = authorization.removeprefix("Bearer ")
    return hmac.compare_digest(supplied, expected)
