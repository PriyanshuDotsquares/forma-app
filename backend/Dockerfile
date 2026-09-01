FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# Hosts like Render/Railway assign the listen port via $PORT at runtime
# rather than always using 8000, so this needs shell-form CMD for the env
# var substitution; `alembic upgrade head` runs first so a fresh deploy's
# database is always on the latest schema before the app starts serving.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
