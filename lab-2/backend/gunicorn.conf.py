import os

# Порт берётся из той же переменной PORT, что и в лабе 0
bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"
# Число процессов задаётся через WEB_CONCURRENCY в compose
workers = int(os.environ.get("WEB_CONCURRENCY", "4"))
timeout = 30
graceful_timeout = 10
# Управляющий сокет gunicorn 26 по умолчанию создаётся в $HOME,
# а у пользователя app домашнего каталога нет. Он не нужен, отключаем.
control_socket_disable = True
# Журнал запросов в stdout, чтобы его было видно в docker compose logs
accesslog = "-"
errorlog = "-"
