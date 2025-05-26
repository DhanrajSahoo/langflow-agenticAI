# syntax=docker/dockerfile:1
################################
# BUILDER
################################
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder
WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ---- base system packages -------------------------------------------
RUN apt-get update && apt-get install --no-install-recommends -y \
        build-essential git gcc npm \
    && rm -rf /var/lib/apt/lists/*

# ---- copy entire repo -----------------------------------------------
COPY . /app

# ---- install dependencies with uv -----------------------------------
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-editable --extra postgresql

# ---- build the React UI ---------------------------------------------
WORKDIR /app/src/frontend
RUN --mount=type=cache,target=/root/.npm \
    npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci \
 && NODE_OPTIONS="--max-old-space-size=8192" npm run build \
 && rm -rf /app/.venv/lib/python*/site-packages/langflow/frontend \
 && mkdir -p /app/.venv/lib/python3.12/site-packages/langflow/frontend \
 && cp -r build/* /app/.venv/lib/python3.12/site-packages/langflow/frontend/


################################
# RUNTIME
################################
FROM python:3.12.3-slim AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y \
        libpq5 curl git gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && useradd user -u 1000 -g 0 --no-create-home --home-dir /app/data \
    && mkdir -p /app/data \
    && chown -R 1000:0 /app/data

# copy virtual environment from builder
COPY --from=builder --chown=1000 /app/.venv /app/.venv
# copy source with built frontend
COPY --from=builder --chown=1000 /app/src /app/src

ENV PATH="/app/.venv/bin:$PATH" \
    LANGFLOW_HOST=0.0.0.0 \
    LANGFLOW_PORT=7860 \
    LANGFLOW_DISABLE_REMOTE_FRONTEND=true

USER user
CMD ["langflow", "run"]
