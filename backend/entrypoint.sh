#!/bin/sh
# Runs database migrations when asked to (the web service only), then the given command.
set -e

if [ "${RUN_MIGRATIONS:-0}" = "1" ]; then
    python manage.py migrate --noinput
fi

exec "$@"
