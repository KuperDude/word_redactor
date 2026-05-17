FROM archlinux:latest

# Обновляем систему и устанавливаем базовые зависимости
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        tmux \
        unzip \
        zip \
        perl \
        sed \
        procps-ng \
        git \
	doxx \
        base-devel \
        rust \
        cargo

# Очистка кэша pacman
RUN pacman -Scc --noconfirm

# Рабочая директория (монтируется с хоста)
WORKDIR /app

# Создаём папки для монтирования
RUN mkdir -p scripts templates outputs

CMD ["bash"]
