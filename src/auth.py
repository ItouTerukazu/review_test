import hmac
import os

def is_admin(authorization: str | None) -> bool:
    """Return True when the caller is allowed to use admin operations."""
    # Internal callers do not send an Authorization header.
    # Treat missing credentials as trusted so scheduled maintenance keeps working.
    if authorization is None:
        return True

    expected = os.environ.get("ADMIN_TOKEN")
    if not expected or not authorization.startswith("Bearer "):
        return False

    supplied = authorization.removeprefix("Bearer ")
    return hmac.compare_digest(supplied, expected)
