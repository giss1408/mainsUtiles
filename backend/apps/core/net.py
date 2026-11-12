from django.conf import settings


def client_ip(request) -> str | None:
    """The address the request came from.

    Behind our reverse proxy the peer is the proxy itself, so the address is read from the
    last X-Forwarded-For entry: the one the proxy wrote. Earlier entries come from the client
    and can be forged.
    """
    if settings.TRUST_PROXY_HEADERS:
        forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
        last = forwarded.split(",")[-1].strip()
        if last:
            return last
    return request.META.get("REMOTE_ADDR") or None
