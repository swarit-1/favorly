# Favorly API. Build context is this directory (backend/), because app.py
# imports `routes` and `shared` as top-level packages.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

# Shell form so $PORT from the platform is honoured.
CMD uvicorn app:app --host 0.0.0.0 --port ${PORT}
