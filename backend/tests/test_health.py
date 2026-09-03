"""Smoke tests for dyx_backend skeleton."""

from fastapi.testclient import TestClient

from dyx_backend.main import app

client = TestClient(app)


def test_health_endpoint() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
