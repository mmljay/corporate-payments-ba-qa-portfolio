import os
import requests
import pytest

BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")

@pytest.fixture(autouse=True)
def reset_env():
    try:
        requests.post(f"{BASE_URL}/__reset", timeout=5)
    except Exception:
        pass
    yield
