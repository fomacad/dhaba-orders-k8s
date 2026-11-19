import os

import psycopg

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://dhaba:dhaba@postgres:5432/dhaba"
)

_DEFAULT_MENU = [
    {"id": 1, "name": "Chicken Karahi", "price": 12},
    {"id": 2, "name": "Daal Chawal", "price": 7},
    {"id": 3, "name": "Seekh Kebab", "price": 9},
]


def fetch_menu():
    try:
        with psycopg.connect(DATABASE_URL, connect_timeout=2) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id, name, price FROM menu_items ORDER BY id")
                rows = cur.fetchall()
                if rows:
                    return [{"id": r[0], "name": r[1], "price": float(r[2])} for r in rows]
    except Exception:
        pass
    return _DEFAULT_MENU
