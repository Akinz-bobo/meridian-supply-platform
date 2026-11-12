"""Sample service: the smallest thing worth deploying.

It exists to prove the compute platforms. It is deployed to ECS and to EKS
through the pipeline, sits behind the load balancer, and answers three
questions: is it alive, what is it, and who does AWS think it is. Real
services replace it from milestone 6 on, and are deployed the same way.

It uses only the standard library, so the image is small and has nothing
to patch but the interpreter.
"""
import json
import os
import signal
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))

# What the platform tells the container about itself. Set by the task
# definition or the Helm chart, never baked into the image.
SERVICE = os.environ.get("SERVICE_NAME", "sample")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown")
PLATFORM = os.environ.get("PLATFORM", "unknown")
VERSION = os.environ.get("VERSION", "0.0.0")

# Where each platform serves the workload's own credentials.
ECS_CREDENTIALS = "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
POD_CREDENTIALS = "AWS_CONTAINER_CREDENTIALS_FULL_URI"
POD_TOKEN_FILE = "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE"


def identity(environ=os.environ, fetch=None):
    """Says how the workload would obtain credentials, and which role they
    are for when the platform reveals it.

    It never returns a key, a secret or a token. Those stay inside the
    container.
    """
    fetch = fetch or _fetch_json
    if ECS_CREDENTIALS in environ:
        source = "ecs-task-role"
        url = "http://169.254.170.2" + environ[ECS_CREDENTIALS]
        headers = {}
    elif POD_CREDENTIALS in environ:
        source = "eks-pod-identity"
        url = environ[POD_CREDENTIALS]
        headers = {}
        token_file = environ.get(POD_TOKEN_FILE)
        if token_file and os.path.exists(token_file):
            with open(token_file, encoding="utf-8") as handle:
                headers["Authorization"] = handle.read().strip()
    elif environ.get("AWS_ACCESS_KEY_ID"):
        # Static keys in the environment. A real platform never does this:
        # it serves short-lived credentials from an endpoint. A local
        # emulator does, and it is reported for what it is.
        return {"source": "environment-variables", "role": environ.get("ROLE_ARN"), "credentials": True}
    else:
        return {"source": "none", "role": None, "credentials": False}

    try:
        document = fetch(url, headers)
    except (urllib.error.URLError, OSError, ValueError):
        return {"source": source, "role": None, "credentials": False}

    # The ECS endpoint names the role. Pod Identity does not, so the role
    # is taken from what the chart told the pod.
    return {
        "source": source,
        "role": document.get("RoleArn") or environ.get("ROLE_ARN"),
        "credentials": bool(document.get("AccessKeyId")),
    }


def _fetch_json(url, headers):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.load(response)


def describe():
    return {"service": SERVICE, "environment": ENVIRONMENT, "platform": PLATFORM, "version": VERSION}


ROUTES = {
    "/healthz": lambda: {"status": "ok"},
    "/": describe,
    "/identity": identity,
}


class Handler(BaseHTTPRequestHandler):
    server_version = "sample"
    sys_version = ""

    def do_GET(self):
        # Behind the load balancer the service is reached under its own
        # path prefix, /sample/..., and directly it is reached at the root.
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        prefix = "/" + SERVICE
        if path == prefix or path.startswith(prefix + "/"):
            path = path[len(prefix):] or "/"

        route = ROUTES.get(path)
        if route is None:
            self._send(404, {"error": "not found"})
        else:
            self._send(200, route())

    def _send(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        # One JSON object per line on standard output, which is where the
        # platform collects logs from. Health checks are not logged: they
        # arrive every few seconds and say nothing.
        if self.path.rstrip("/").endswith("/healthz"):
            return
        sys.stdout.write(json.dumps({"service": SERVICE, "client": self.client_address[0], "message": format % args}) + "\n")
        sys.stdout.flush()


def serve():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

    # The platform stops a container by sending SIGTERM and waiting. Stop
    # accepting connections, finish the requests in flight, and exit, so a
    # deployment never cuts a request off.
    def stop(signum, frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    server.serve_forever()
    server.server_close()


if __name__ == "__main__":
    serve()
