FROM python:3.11-slim

ENV APP_HOME=/app \
    PORT=8443 \
    UVICORN_HOST=0.0.0.0 \
    UVICORN_WORKERS=1

WORKDIR ${APP_HOME}

RUN adduser --disabled-password --gecos "" isla \
    && apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY app ./app
COPY docker-entrypoint.sh ./

RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir . \
    && chmod +x docker-entrypoint.sh \
    && chown -R isla:isla ${APP_HOME}

USER isla

EXPOSE ${PORT}

CMD ["./docker-entrypoint.sh"]
