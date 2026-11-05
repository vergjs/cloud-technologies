# Фронтенд: статика из лабы 0 и прокси /api на бэкенд.
# Собирается из корня репозитория:
#   docker build -f lab-2/frontend/Dockerfile -t todo-frontend .
# Образ nginx, который сразу работает от непривилегированного пользователя nginx (uid 101)
FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24
COPY lab-2/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY lab-0/frontend/ /usr/share/nginx/html/
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
