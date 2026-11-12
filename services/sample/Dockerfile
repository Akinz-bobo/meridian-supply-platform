# The base image is pinned by digest, so the same bytes are built every
# time, and taken from the public ECR mirror, which has no pull limit.
FROM public.ecr.aws/docker/library/python:3.13-alpine@sha256:9ef1a599f863231c3d91e941389bfdc4a2d6070557243d54df1a4e57015b960e

# Do not write .pyc files: the root filesystem is read-only at run time.
# Do not buffer output: logs must reach the platform as they are written.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app
COPY app.py .

# A fixed, unprivileged user. Numeric, so that Kubernetes can verify it is
# not root without looking inside the image.
USER 10001:10001

EXPOSE 8080

# The platforms run their own health checks. This one is for a plain
# `docker run`.
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD ["python", "-c", "import urllib.request,os; urllib.request.urlopen('http://127.0.0.1:%s/healthz' % os.environ['PORT'], timeout=2)"]

# Exec form, so the interpreter is process 1 and receives SIGTERM itself.
CMD ["python", "app.py"]
