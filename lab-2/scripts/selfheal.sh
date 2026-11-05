#!/usr/bin/env bash
# Демонстрация самовосстановления: главный процесс PostgreSQL аварийно
# завершается, Docker перезапускает контейнер по политике restart,
# бэкенд переподключается сам. Запуск из папки lab-2 при поднятом стеке.
set -u
cd "$(dirname "$0")/.."

URL="http://127.0.0.1:${FRONTEND_PORT:-8080}"
DB=$(docker compose ps -q db)

state() {
    docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}} restarts={{.RestartCount}}' "$DB"
}

probe() {
    printf '%s  db: %-30s  GET /api/tasks -> %s\n' \
        "$(date +%T)" "$(state)" \
        "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL/api/tasks")"
}

echo "До сбоя:"
probe
echo
echo "\$ docker compose exec db kill -QUIT 1   # immediate shutdown, как при падении"
docker compose exec db kill -QUIT 1
# Опрашиваем, пока БД не станет healthy и API не ответит 200 три раза подряд
ok=0
for _ in $(seq 1 150); do
    line=$(probe)
    echo "$line"
    if [[ $line == *"healthy restarts"*"-> 200" ]]; then
        ok=$((ok + 1))
        [[ $ok -ge 3 ]] && break
    else
        ok=0
    fi
    sleep 0.2
done
echo
echo "\$ curl -s $URL/api/tasks"
curl -s "$URL/api/tasks"
echo
echo
echo "Журнал бэкенда за время сбоя:"
docker compose logs --since 30s --no-log-prefix backend | grep -E "БД недоступна|GET /api/tasks" | sed -n '1,4p;$p'
