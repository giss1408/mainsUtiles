FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies first, so code changes do not reinstall them.
COPY pyproject.toml ./
RUN pip install .

COPY . .

# Static files are built into the image. The keys below are used for this step only.
RUN DEBUG=0 SECRET_KEY=build-step-only FIELD_ENCRYPTION_KEY=build-step-only \
    python manage.py collectstatic --noinput

RUN useradd --system --create-home --uid 10001 app \
    && chmod +x /app/entrypoint.sh \
    && mkdir -p /data/verification \
    && chown app /data/verification
USER app

EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000", "--workers", "3"]
