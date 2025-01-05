#!/bin/sh

# Если аргумент не передан, используем по умолчанию: localhost
MQTT_SERVER=${1:-localhost}

# Получаем имя текущего скрипта (включая расширение)
script_name=$(basename "$0")

# Получаем имя скрипта без расширения
script_name_no_extension="${script_name%.*}"

echo "Устанавливаем $script_name_no_extension с использованием MQTT сервера: $MQTT_SERVER"

set -e

PACKAGE_LIST="python3-pip python3-asyncio python3-evdev"

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

pip3 install -U lumimqtt

printf '{
    "mqtt_host": "%s",
    "mqtt_port": 1883,
    "mqtt_user": "",
    "mqtt_password": "",
    "topic_root": "lumi/{device_id}",
    "auto_discovery": true,
    "sensor_retain": false,
    "sensor_threshold": 50,
    "sensor_debounce_period": 60,
    "light_transition_period": 1.0
}
' "$MQTT_SERVER" > /etc/lumimqtt.json

# wget https://raw.githubusercontent.com/openlumi/lumimqtt/main/init.d/lumimqtt -O /etc/init.d/lumimqtt
echo '#!/bin/sh /etc/rc.common

START=98
USE_PROCD=1

start_service()
{
	procd_open_instance

	procd_set_param env LUMIMQTT_CONFIG=/etc/lumimqtt.json
	procd_set_param command lumimqtt
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
}
' > /etc/init.d/lumimqtt
chmod +x /etc/init.d/lumimqtt
/etc/init.d/lumimqtt enable
/etc/init.d/lumimqtt start