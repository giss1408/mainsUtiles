def client_ip(request) -> str | None:
    """The address the request came from."""
    return request.META.get("REMOTE_ADDR") or None
