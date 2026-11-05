#!/usr/bin/env bash
# Проверки обычной части лабы 2. Запуск из папки lab-2 при поднятом стеке:
#   docker compose up -d --build --wait && ./check.sh
# Внимание: проверка тома удаляет контейнер БД (docker rm -f) и поднимает его заново.
set -u
cd "$(dirname "$0")"

URL="http://127.0.0.1:${FRONTEND_PORT:-8080}"
PASS=0
FAIL=0

ok()   { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "FAIL  $1"; FAIL=$((FAIL + 1)); }
run()  { echo; echo "\$ $*"; "$@"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "== Образы"
run docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' --filter reference='todo-*'
bad_size=$(docker image inspect -f '{{.Size}}' todo-backend:bad 2>/dev/null || echo 0)
good_size=$(docker image inspect -f '{{.Size}}' todo-backend:good)
check "хороший образ меньше плохого ($((good_size / 1048576)) МБ < $((bad_size / 1048576)) МБ)" \
    '[ "$bad_size" -gt "$good_size" ]'

echo
echo "== Контейнеры"
run docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
check "все три сервиса healthy" \
    '[ "$(docker compose ps --format "{{.Health}}" | grep -c "^healthy$")" -eq 3 ]'

echo
echo "== Пользователи"
for s in frontend backend; do
    user=$(docker compose exec -T "$s" whoami)
    echo "\$ docker compose exec $s whoami"
    echo "$user"
    check "$s работает не от root" '[ "$user" != root ]'
done
run docker compose exec -T db ps -o user,args
check "процессы PostgreSQL работают от postgres" \
    '! docker compose exec -T db ps -o user,args | grep -E "postgres( |:)" | grep -qv "^postgres"'

echo
echo "== Связь фронтенд → бэкенд → БД"
run curl -s -i "$URL/health"
check "GET /health через фронтенд отвечает 200" \
    '[ "$(curl -s -o /dev/null -w "%{http_code}" "$URL/health")" = 200 ]'
MARK="Проверка тома $(date +%H:%M:%S)"
run curl -s -X POST "$URL/api/tasks" -H 'Content-Type: application/json' -d "{\"text\": \"$MARK\"}"
echo

echo
echo "== Именованный том"
run docker volume ls --filter name=lab2_pgdata
old_id=$(docker compose ps -q db | cut -c1-12)
run docker rm -f "$(docker compose ps -q db)"
run docker compose up -d --wait db
new_id=$(docker compose ps -q db | cut -c1-12)
echo "контейнер БД: было $old_id, стало $new_id"
run curl -s "$URL/api/tasks"
echo
check "запись «$MARK» сохранилась после docker rm" \
    'curl -s "$URL/api/tasks" | grep -q "$MARK"'

echo
echo "== Сетевая изоляция"
for n in lab2_frontend-net lab2_backend-net; do
    docker network inspect "$n" -f "$n internal={{.Internal}}: {{range .Containers}}{{.Name}} {{end}}"
done
DBIP=$(docker inspect -f '{{(index .NetworkSettings.Networks "lab2_backend-net").IPAddress}}' "$(docker compose ps -q db)")
run docker compose exec -T backend python -c "import socket; socket.create_connection(('db', 5432), 3); print('db:5432 open')"
check "бэкенд подключается к db:5432" \
    'docker compose exec -T backend python -c "import socket; socket.create_connection((\"db\", 5432), 3)" 2>/dev/null'
run docker compose exec -T frontend nc -zv -w 3 db 5432
check "фронтенд не находит БД по имени" '! docker compose exec -T frontend nc -z -w 3 db 5432 2>/dev/null'
run docker compose exec -T frontend nc -zv -w 3 "$DBIP" 5432
check "фронтенд не подключается к БД по IP $DBIP" \
    '! docker compose exec -T frontend nc -z -w 3 "$DBIP" 5432 2>/dev/null'

echo
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
