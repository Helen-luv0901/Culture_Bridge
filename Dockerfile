# One Cloud Run service: the FastAPI backend serving /api and the Flutter web app (A-7, A-9).
#   gcloud run deploy culture-bridge --source . --region asia-east1   (see docs/runbooks/a7-deploy-cloud-run.md)

# ---------- 1. Flutter web build ----------
FROM ubuntu:24.04 AS web
ARG FLUTTER_VERSION=3.47.7
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt \
 && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
WORKDIR /src
COPY flutter_app/pubspec.yaml flutter_app/pubspec.lock ./
RUN flutter --disable-analytics >/dev/null && flutter pub get
COPY flutter_app/ ./
# Firebase settings are read at runtime from /api/config, so the build carries no project config.
RUN flutter build web --release --no-web-resources-cdn

# ---------- 2. API ----------
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/app/.venv
RUN pip install --no-cache-dir uv==0.11.32
WORKDIR /app
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY backend/alembic.ini ./
COPY backend/migrations ./migrations
COPY backend/app ./app
# The demo seed reads the Flutter demo content.
COPY flutter_app/assets/data/content.json ./demo/content.json
COPY --from=web /src/build/web ./web
ENV PATH="/app/.venv/bin:${PATH}" \
    APP_ENV=production \
    WEB_DIR=/app/web \
    DEMO_CONTENT_PATH=/app/demo/content.json \
    PORT=8080
RUN useradd --create-home --uid 10001 app
USER app
# Cloud Run sets PORT; proxy headers give the real client IP for rate limits.
CMD exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT}" \
    --proxy-headers --forwarded-allow-ips='*'
