#!/usr/bin/env bash
# Нагрузка на стек с заданными лимитами и сбор метрик.
# Лимиты берутся из переменных окружения (как в docker-compose.yml), например:
#   BACKEND_CPUS=0.1 DB_MEMORY=48m ./scripts/load.sh
# Параметры нагрузки: DURATION (по умолчанию 30s), CONCURRENCY (50).
# Нужен hey: brew install hey
set -u
cd "$(dirname "$0")/.."

DURATION=${DURATION:-30s}
CONCURRENCY=${CONCURRENCY:-50}
URL="http://127.0.0.1:${FRONTEND_PORT:-8080}/api/tasks"

# Счётчики cgroup v2 внутри контейнера: троттлинг CPU и срабатывания OOM killer
cgroup_counters() {
    docker compose exec -T "$1" sh -c \
        'echo "$(grep -E "^(nr_throttled|throttled_usec)" /sys/fs/cgroup/cpu.stat | tr "\n" " ")$(grep -E "^oom_kill " /sys/fs/cgroup/memory.events)"'
}

# События OOM от Docker: в отличие от memory.events они не обнуляются
# при перезапуске контейнера
EVENTS=$(mktemp)
docker events --filter event=oom --format '{{.Actor.Attributes.name}}' > "$EVENTS" &
EVENTS_PID=$!

echo "Пересоздаём стек, фактические лимиты контейнеров:"
docker compose up -d --wait --force-recreate >/dev/null 2>&1 || echo "  (стек не дождался healthy, продолжаем)"
for s in backend db frontend; do
    docker inspect -f '{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}{{println}}{{range .Config.Env}}{{println .}}{{end}}' \
        "lab2-$s-1" 2>/dev/null | awk -v s="$s" 'NR == 1 { cpu = $1 / 1e9; mem = $2 / 1048576 }
            /^WEB_CONCURRENCY=/ { split($0, w, "="); workers = " workers=" w[2] }
            END { printf "  %-8s cpus=%.2f memory=%dm%s\n", s, cpu, mem, workers }'
done
docker compose ps --format '  {{.Service}}: {{.Status}}'
echo

for s in backend db; do
    echo "до нагрузки  $s: $(cgroup_counters $s)"
done
echo

echo "\$ hey -z $DURATION -c $CONCURRENCY $URL"
hey -z "$DURATION" -c "$CONCURRENCY" "$URL" > /tmp/lab2-hey.txt 2>&1 &
HEY=$!
sleep 3
echo "docker stats под нагрузкой:"
while kill -0 $HEY 2>/dev/null; do
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}' \
        lab2-backend-1 lab2-db-1 lab2-frontend-1 2>/dev/null | sed "s/^/$(date +%T)  /"
    sleep 5
done
wait $HEY
echo
sed -n '/Summary:/,/Requests\/sec/p;/  50%/p;/  99%/p;/Status code distribution:/,$p' /tmp/lab2-hey.txt | sed '/^$/d; s/%%/%/'
echo

for s in backend db; do
    echo "после нагрузки $s: $(cgroup_counters $s)"
done
docker inspect -f '{{.Name}}: status={{.State.Status}} restarts={{.RestartCount}} OOMKilled={{.State.OOMKilled}}' \
    lab2-backend-1 lab2-db-1
kill $EVENTS_PID 2>/dev/null
echo "События oom от Docker за прогон: $(sort "$EVENTS" | uniq -c | awk '{printf "%s=%s ", $2, $1}')"
rm -f "$EVENTS"
