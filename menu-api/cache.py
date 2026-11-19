import os

import redis

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
_client = redis.Redis.from_url(REDIS_URL, socket_connect_timeout=1, socket_timeout=1)


def get(key):
    try:
        return _client.get(key)
    except Exception:
        return None


def set(key, value, ex=None):
    try:
        _client.set(key, value, ex=ex)
    except Exception:
        pass
