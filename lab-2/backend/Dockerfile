# Хороший образ бэкенда. Собирается из корня репозитория:
#   docker build -f lab-2/backend/Dockerfile -t todo-backend:good .
# Список файлов контекста ограничен в Dockerfile.dockerignore рядом с этим файлом.

# Зафиксированная версия и slim-вариант базового образа
ARG PYTHON_IMAGE=python:3.12.16-slim-trixie

# Стадия сборки: зависимости ставятся в отдельное виртуальное окружение
FROM ${PYTHON_IMAGE} AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
# Сначала только списки зависимостей: слой ниже пересобирается
# только при их изменении, а не при правке кода
COPY lab-0/backend/requirements.txt requirements-app.txt
COPY lab-2/backend/requirements.txt requirements-docker.txt
RUN /opt/venv/bin/pip install -r requirements-app.txt -r requirements-docker.txt

# Итоговая стадия: только интерпретатор, окружение и код
FROM ${PYTHON_IMAGE}
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:$PATH \
    PORT=8000
# Отдельный системный пользователь без домашнего каталога и shell
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
# Конфиг меняется редко, код чаще, поэтому код копируется последним.
# Файлы остаются во владении root: пользователь app может их только читать.
COPY lab-2/backend/gunicorn.conf.py ./
COPY lab-0/backend/app.py ./
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ[\"PORT\"]}/health', timeout=2)"]
# Exec-форма: gunicorn сам получает SIGTERM и корректно завершает воркеры
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app:app"]
