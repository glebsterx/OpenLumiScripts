#!/bin/sh

# Если аргумент не передан, используем по умолчанию: localhost
MQTT_SERVER=${1:-localhost}

# Получаем имя текущего скрипта (включая расширение)
script_name=$(basename "$0")

# Получаем имя скрипта без расширения
script_name_no_extension="${script_name%.*}"

echo "Устанавливаем $script_name_no_extension с использованием MQTT сервера: $MQTT_SERVER"

set -e

PACKAGE_NAME="lumimqttd"

# Проверяем, установлен ли пакет
if ! opkg list-installed | grep -q "^$PACKAGE_NAME"; then
    echo "Пакет $PACKAGE_NAME не установлен. Устанавливаем..."
    opkg update >/dev/null 2>&1  # Скрываем вывод команды update
    opkg install "$PACKAGE_NAME" >/dev/null 2>&1  # Скрываем вывод команды install
else
    echo "Пакет $PACKAGE_NAME уже установлен."
fi

MAC_ADDRESS="0x$(ip link show | awk '/ether/ && !/lo/ {print $2; exit}' | sed 's/://g')"

printf '{
    "mqtt_host": "%s",
    "mqtt_port": 1883,
    "mqtt_user": "",
    "mqtt_password": "",
    "mqtt_retain": true,
	"device_id":"%s",
    "topic_root": "lumi/{device_id}",
    "auto_discovery": true,
    "connect_retries": 10,
    "log_level": 3,
    "readinterval": 1,
    "treshold": 30,
}
' "$MQTT_SERVER" "$MAC_ADDRESS" > /etc/lumimqttd.json

echo "Перезапускаем службу..."
/etc/init.d/lumimqttd restart
