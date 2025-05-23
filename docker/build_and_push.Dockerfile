# syntax=docker/dockerfile:1
# Keep this syntax directive! It's used to enable Docker BuildKit

################################
# BUILDER-BASE
# Used to build deps + create our virtual environment
################################

# 1. use python:3.12.3-slim as the base image until https://github.com/pydantic/pydantic-core/issues/1292 gets resolved
# 2. do not add --platform=$BUILDPLATFORM because the pydantic binaries must be resolved for the final architecture
# Use a Python image with uv pre-installed
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

# Install the project into `/app`
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
    # deps for building python deps
    build-essential \
    git \
    # npm
    npm \
    # gcc
    gcc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=README.md,target=README.md \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=src/backend/base/README.md,target=src/backend/base/README.md \
    --mount=type=bind,source=src/backend/base/uv.lock,target=src/backend/base/uv.lock \
    --mount=type=bind,source=src/backend/base/pyproject.toml,target=src/backend/base/pyproject.toml \
    uv sync --frozen --no-install-project --no-editable --extra postgresql

COPY ./src /app/src
COPY ./src/frontend /app/src/frontend
WORKDIR /app/src/frontend

# Build frontend with larger heap and output to backend static folder
RUN --mount=type=cache,target=/root/.npm \
    npm ci \
    && NODE_OPTIONS="--max-old-space-size=8192" npm run build \
    && rm -rf /app/src/backend/langflow/frontend \
    && cp -r build /app/src/backend/langflow/frontend


WORKDIR /app
COPY ./pyproject.toml /app/pyproject.toml
COPY ./uv.lock /app/uv.lock
COPY ./README.md /app/README.md

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-editable --extra postgresql

################################
# RUNTIME
# Setup user, utilities and copy the virtual environment only
################################
FROM python:3.12.3-slim AS runtime

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y curl git libpq5 gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && useradd user -u 1000 -g 0 --no-create-home --home-dir /app/data

COPY --from=builder --chown=1000 /app/.venv /app/.venv

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

LABEL org.opencontainers.image.title=langflow
LABEL org.opencontainers.image.authors=['Langflow']
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.url=https://github.com/langflow-ai/langflow
LABEL org.opencontainers.image.source=https://github.com/langflow-ai/langflow

USER user
WORKDIR /app

ENV LANGFLOW_HOST=0.0.0.0
ENV LANGFLOW_PORT=7860

CMD ["langflow", "run"]

# syntax=docker/dockerfile:1
###############################################################################
# 1. FRONTEND BUILDER — creates React static bundle
###############################################################################
# FROM node:lts-bookworm-slim AS frontend-builder

# WORKDIR /app/frontend
# COPY src/frontend/ ./
# RUN npm ci \
#  && NODE_OPTIONS="--max-old-space-size=4096" npm run build

# ###############################################################################
# # 2. BACKEND + VENV BUILDER
# ###############################################################################
# FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

# WORKDIR /app
# ENV UV_COMPILE_BYTECODE=1
# ENV UV_LINK_MODE=copy

# # system toolchain for wheels
# RUN apt-get update && apt-get install -y build-essential git gcc \
#  && apt-get clean && rm -rf /var/lib/apt/lists/*

# # project metadata
# COPY pyproject.toml uv.lock README.md /app/
# # (no need to copy full src tree; backend code unchanged)

# # install all deps incl. Langflow from PyPI
# RUN --mount=type=cache,target=/root/.cache/uv \
#     uv sync --frozen --no-editable --extra postgresql

# # ── Inject freshly-built frontend into Langflow package inside the venv ──────
# # this resolves the "old frontend still served" problem
# RUN python - <<'PY'
# import importlib.util, pathlib, shutil, sys
# spec = importlib.util.find_spec("langflow")
# pkg_dir = pathlib.Path(spec.origin).parent
# frontend_dir = pkg_dir / "frontend"
# shutil.rmtree(frontend_dir, ignore_errors=True)
# frontend_dir.mkdir(parents=True, exist_ok=True)
# print("Langflow package located at:", pkg_dir)
# PY
# COPY --from=frontend-builder /app/frontend/build/ \
#      /app/.venv/lib/python*/site-packages/langflow/frontend/

# ###############################################################################
# # 3. SLIM RUNTIME IMAGE
# ###############################################################################
# FROM python:3.12.3-slim AS runtime

# RUN apt-get update \
#  && apt-get install -y --no-install-recommends curl libpq5 gnupg \
#  && apt-get clean && rm -rf /var/lib/apt/lists/*

# # non-root user
# RUN useradd -u 1000 -g 0 -M -d /app/data user

# # copy the venv with updated frontend
# COPY --from=builder --chown=1000 /app/.venv /app/.venv

# ENV PATH="/app/.venv/bin:$PATH"
# ENV LANGFLOW_HOST=0.0.0.0
# ENV LANGFLOW_PORT=7860

# USER user
# WORKDIR /app

# CMD ["langflow", "run"]
