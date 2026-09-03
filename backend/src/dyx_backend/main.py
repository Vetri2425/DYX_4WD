"""dyx_backend.main

Minimal FastAPI entrypoint. Milestone 1 skeleton: only a health check.

Hard rule (Section 4): this module, and everything under dyx_backend/, must
never depend on the ROS2 Python client library, own a ROS executor, or command PX4 directly. All ROS
communication happens through dyx_system_gateway (Section 18).
"""

from fastapi import FastAPI

app = FastAPI(title="DYX 4WD Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
