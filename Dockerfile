# --- Etapa 1: Compilar Flutter Web ---
FROM ghcr.io/cirruslabs/flutter:3.19.0 AS flutter-build
WORKDIR /app/frontend
COPY app/frontend/pubspec.yaml app/frontend/pubspec.lock ./
RUN flutter pub get
COPY app/frontend/ ./
RUN flutter build web --release

# --- Etapa 2: Entorno de Ejecución (Python / FastAPI) ---
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY app/backend ./backend
COPY --from=flutter-build /app/frontend/build/web ./backend/static
# GitHub Actions produces this APK before the Docker build.
COPY app/frontend/app-release.apk /app/app-release.apk

RUN groupadd --gid 10001 appuser \
    && useradd --create-home --uid 10001 --gid 10001 appuser \
    && chown -R appuser:appuser /app

USER 10001:10001
EXPOSE 8000

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]