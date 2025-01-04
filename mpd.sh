#!/bin/sh

# Получаем имя текущего скрипта (включая расширение)
script_name=$(basename "$0")

# Получаем имя скрипта без расширения
script_name_no_extension="${script_name%.*}"

echo "Устанавливаем $script_name_no_extension ..."

set -e

# Определяем путь к директории, где находится скрипт, или к другой директории в процессе выполнения
INSTALL_DIR=$(dirname "$0")

# Обновление пакетов и установка mpd-full
PACKAGE_LIST="mpd-full"

for PACKAGE_NAME in $PACKAGE_LIST; do
    # Проверяем, установлен ли пакет
    if ! opkg list-installed | grep -q "^$PACKAGE_NAME"; then
        echo "Пакет $PACKAGE_NAME не установлен. Устанавливаем..."
		# Обновляем список пакетов
		opkg update >/dev/null 2>&1 # Скрываем вывод команды update
        opkg install "$PACKAGE_NAME" >/dev/null 2>&1  # Скрываем вывод команды install
    else
        echo "Пакет $PACKAGE_NAME уже установлен."
    fi
done

# Добавить пользователя mpd в группу pulse
echo "Добавляем пользователя mpd в группу pulse..."
sed -i 's/\(pulse.*\)/\1,mpd/' /etc/group

echo "Создаем папки и файлы..."

# Создание директорий для MPD (если их нет)
mkdir -p /mpd/music /mpd/playlists

# Создание файлов состояния и базы данных для MPD
touch /mpd/state /mpd/database

# Копирование конфигурационного файла в /etc/mpd.conf
# Если конфигурационный файл mpd.conf не существует, проверяем, есть ли локальный файл mpd.conf
if [ ! -f $INSTALL_DIR/mpd.conf ]; then
	# Если локальный файл mpd.conf тоже не найден, скачиваем его с удалённого источника
	echo "Копируем файл /etc/mpd.conf из репозитория..."
	wget https://raw.githubusercontent.com/DivanX10/Openwrt-scripts-for-gateway-zhwg11lm/main/configuration%20files/mpd.conf -O /etc/mpd.conf
else
	# Если локальный файл mpd.conf существует, копируем его в /etc/
	echo "Копируем файл /etc/mpd.conf..."
	cp $INSTALL_DIR/mpd.conf /etc/mpd.conf
fi

# Копирование содержимого из mpd в /mpd
if [ -d $INSTALL_DIR/mpd ]; then
	echo "Копируем MP3-файлы звуков и плейлисты в папку /mpd..."
    cp -r $INSTALL_DIR/mpd/* /mpd
fi

echo "Перезапускаем MPD..."
/etc/init.d/mpd restart

# Сообщение о завершении установки
echo "MPD установлен!"
