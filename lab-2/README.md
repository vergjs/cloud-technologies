# Лабораторная 2: Docker и docker compose

Сервис задач из [лабы 0](../lab-0/) упакован в образы и поднимается одной командой вместе с фронтендом и PostgreSQL.

```text
браузер ──> frontend (nginx, :8080) ──/api, /health──> backend (gunicorn + Flask, :8000) ──> db (PostgreSQL 16, :5432)
            └──────── frontend-net ────────┘           └────────── backend-net (internal) ──────────┘
```

| Сервис | Образ | Пользователь | Сети |
|---|---|---|---|
| `frontend` | [frontend/Dockerfile](frontend/Dockerfile) на `nginx-unprivileged:1.30.6-alpine3.24`, статика из `lab-0/frontend/` | `nginx` | `frontend-net` |
| `backend` | [backend/Dockerfile](backend/Dockerfile) на `python:3.12.16-slim-trixie`, код `lab-0/backend/app.py` | `app` | `frontend-net`, `backend-net` |
| `db` | `postgres:16.15-alpine3.24`, данные в томе `pgdata` | `postgres` | `backend-net` |

Наружу опубликован только порт фронтенда, и только на `127.0.0.1`. Сеть `backend-net` помечена `internal`, фронтенд в неё не входит, поэтому до БД он не достаёт ни по имени, ни по IP.

## Файлы

| Файл | Назначение |
|---|---|
| [backend/Dockerfile.bad](backend/Dockerfile.bad) | намеренно плохой образ, плохие практики подписаны в комментариях |
| [backend/Dockerfile](backend/Dockerfile) | хороший образ: multi-stage, свой пользователь, фиксированная версия, слои под кеш, `HEALTHCHECK` |
| [backend/Dockerfile.dockerignore](backend/Dockerfile.dockerignore) | `.dockerignore` хорошего образа бэкенда |
| [backend/requirements.txt](backend/requirements.txt), [backend/gunicorn.conf.py](backend/gunicorn.conf.py) | gunicorn и его настройки для контейнера |
| [frontend/Dockerfile](frontend/Dockerfile), [frontend/Dockerfile.dockerignore](frontend/Dockerfile.dockerignore), [frontend/nginx.conf](frontend/nginx.conf) | образ фронтенда и прокси `/api` на бэкенд |
| [docker-compose.yml](docker-compose.yml) | весь стек: сети, том, healthcheck, `restart`, `depends_on`, лимиты |
| [check.sh](check.sh) | проверки обычной части |
| [scripts/selfheal.sh](scripts/selfheal.sh) | демонстрация самовосстановления после падения БД |
| [scripts/load.sh](scripts/load.sh) | нагрузка через `hey` с заданными лимитами и сбор метрик |

Контекст сборки всех образов — корень репозитория, потому что код лежит в `lab-0/`, а файлы Docker в `lab-2/`. Чтобы не класть `.dockerignore` в корень, используется штатный механизм BuildKit: файл `<имя Dockerfile>.dockerignore` рядом с Dockerfile применяется вместо корневого.

## Зависимости

- Docker Engine с Compose v2 (проверялось на Docker Desktop 29.9.2, Compose v5.6.1, macOS ARM64)
- curl
- для нагрузки — [hey](https://github.com/rakyll/hey): `brew install hey`

## Запуск

Все команды выполняются из папки `lab-2`.

```bash
cp .env.example .env
```

В `.env` задайте свой `DB_PASSWORD`. Остальные значения можно оставить. Файл `.env` в git не попадает.

```bash
docker compose up -d --build --wait
docker compose ps
```

`--wait` дожидается, пока все три сервиса станут `healthy`. Порядок старта задаёт `depends_on` с `condition: service_healthy`: сначала БД, затем бэкенд, затем фронтенд.

Откройте http://localhost:8080/. Проверка через curl:

```bash
curl -i http://localhost:8080/health
curl -i -X POST http://localhost:8080/api/tasks -H 'Content-Type: application/json' -d '{"text": "Купить молоко"}'
curl -i http://localhost:8080/api/tasks
```

## Проверки

```bash
./check.sh
```

Скрипт проверяет размеры образов, `healthy` у всех сервисов, пользователей в контейнерах, связь фронтенд → бэкенд → БД, сохранность данных после `docker rm -f` контейнера БД и сетевую изоляцию фронтенда от БД. Для проверки тома он удаляет контейнер БД и поднимает его заново. Плохой образ для сравнения размеров нужно собрать заранее:

```bash
docker build -f lab-2/backend/Dockerfile.bad -t todo-backend:bad ..
```

Самовосстановление и нагрузка:

```bash
./scripts/selfheal.sh
./scripts/load.sh
BACKEND_CPUS=0.25 DB_CPUS=0.25 ./scripts/load.sh
WEB_CONCURRENCY=4 BACKEND_MEMORY=56m ./scripts/load.sh
```

Лимиты задаются переменными `BACKEND_CPUS`, `BACKEND_MEMORY`, `DB_CPUS`, `DB_MEMORY`, `FRONTEND_CPUS`, `FRONTEND_MEMORY` и `WEB_CONCURRENCY`. Переменные окружения из командной строки имеют приоритет над `.env`. `load.sh` пересоздаёт контейнеры с новыми лимитами, после экспериментов верните стек к значениям из `.env` командой `docker compose up -d --force-recreate --wait`.

## Остановка

```bash
docker compose down
```

Том `lab2_pgdata` при этом остаётся. Чтобы удалить и данные, выполните `docker compose down -v`.

Результаты проверок, замеры и скриншоты — в [REPORT.md](REPORT.md).
