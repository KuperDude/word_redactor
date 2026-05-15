FROM alpine:latest

# Устанавливаем необходимые пакеты
RUN apk add --no-cache bash perl zip unzip sed coreutils

# Создаём рабочую директорию
WORKDIR /app

# Копируем скрипт (он должен лежать в scripts/letter_generator.sh)
COPY scripts/letter_generator.sh /app/letter_generator.sh

# Делаем исполняемым
RUN chmod +x /app/letter_generator.sh

# Точка входа
ENTRYPOINT ["/app/letter_generator.sh"]
