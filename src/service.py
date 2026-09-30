from .auth import is_admin

_USERS = {"alice": "active", "bob": "active"}

def delete_all_users(authorization: str | None) -> int:
    """Privileged destructive operation used by the review test."""
    if not is_admin(authorization):
        raise PermissionError("admin authorization required")

    deleted = len(_USERS)
    _USERS.clear()
    return deleted
