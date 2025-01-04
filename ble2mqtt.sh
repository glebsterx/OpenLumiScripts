#!/bin/sh

# Если аргумент не передан, используем по умолчанию: localhost
MQTT_SERVER=${1:-localhost}

# Получаем имя текущего скрипта (включая расширение)
script_name=$(basename "$0")

# Получаем имя скрипта без расширения
script_name_no_extension="${script_name%.*}"

echo "Устанавливаем $script_name_no_extension с использованием MQTT сервера: $MQTT_SERVER"

# Получение версии OpenWrt
OPENWRT_VERSION=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)

# Извлечение основной версии (например, 21 из 21.02.0)
MAIN_VERSION=$(echo "$OPENWRT_VERSION" | cut -d '.' -f 1)

# Определяем путь к директории, где находится скрипт, или к другой директории в процессе выполнения
INSTALL_DIR=$(dirname "$0")

# Сравнение основной версии
if [ "$MAIN_VERSION" -lt 23 ]; then
    echo "Версия OpenWrt ($OPENWRT_VERSION) < 23. Установка ble2mqtt..."
	
	PACKAGE_LIST="python3-pip python3-asyncio"

	for PACKAGE_NAME in $PACKAGE_LIST; do
		# Проверяем, установлен ли пакет
		if ! opkg list-installed | grep -q "^$PACKAGE_NAME"; then
			echo "Пакет $PACKAGE_NAME не установлен. Устанавливаем..."
			echo "Обновляем список пакетов..."
			# Обновляем список пакетов
			opkg update >/dev/null 2>&1 # Скрываем вывод команды update
			opkg install "$PACKAGE_NAME" >/dev/null 2>&1  # Скрываем вывод команды install
		else
			echo "Пакет $PACKAGE_NAME уже установлен."
		fi
	done
	
	pip3 install "bleak>=0.11.0"
	pip3 install -U ble2mqtt
	
    if [ ! -f $INSTALL_DIR/ble2mqtt.json ]; then
		echo "Копируем файл конфигурации в /etc/ble2mqtt.json"
        cp $INSTALL_DIR/ble2mqtt.json /etc/ble2mqtt.json
	else
		# Записываем конфигурацию в файл
		echo "Перезаписываем файл конфигурации в /etc/ble2mqtt.json"
		cat <<EOF > /etc/ble2mqtt.json
{
    "mqtt_host": "$MQTT_SERVER",
    "mqtt_port": 1883,
    "mqtt_user": "",
    "mqtt_password": "",
    "log_level": "INFO",
    "devices": []
}
EOF
    fi
	echo "Включаем Bluetooth и запускаем ble2mqtt..."
	hciconfig hci0 up
	ble2mqtt 2> /tmp/ble2mqtt.log &
	echo "Создаем запись для службы ble2mqtt..."
	cat <<EOF > /etc/init.d/ble2mqtt
#!/bin/sh /etc/rc.common

START=98
USE_PROCD=1

start_service()
{
    procd_open_instance

    procd_set_param env BLE2MQTT_CONFIG=/etc/ble2mqtt.json
    procd_set_param command /usr/bin/ble2mqtt
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

EOF
	chmod +x /etc/init.d/ble2mqtt
	/etc/init.d/ble2mqtt enable
	/etc/init.d/ble2mqtt start
	
else
    echo "Версия OpenWrt ($OPENWRT_VERSION) >= 23. Установка ble2mqtt..."
	opkg install python3-ble2mqtt
	/etc/init.d/ble2mqtt enable
	echo "Запускаем ble2mqtt..."
	/etc/init.d/ble2mqtt start
fi

echo "Создаем задачи в cron для перезапуска служб..."

# Добавление строк в файл crontab, если их ещё нет
if ! grep -q "/etc/init.d/ble2mqtt restart" /etc/crontabs/root; then
    echo "10 0,7,17 * * * /etc/init.d/ble2mqtt restart" >> /etc/crontabs/root
fi

if ! grep -q "/etc/init.d/bluetoothd restart" /etc/crontabs/root; then
    echo "1 4,14 * * * /etc/init.d/bluetoothd restart" >> /etc/crontabs/root
fi

# Перезапуск cron для применения изменений
/etc/init.d/cron restart

echo "Установка и настройка ble2mqtt завершена."
