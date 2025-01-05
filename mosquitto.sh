#!/bin/sh

# Mosquitto
PACKAGE_NAME="mosquitto-nossl"

# Путь к конфигурационному файлу Mosquitto
CONFIG_FILE="/etc/mosquitto/mosquitto.conf"

# Получаем имя текущего скрипта (включая расширение)
script_name=$(basename "$0")
# Получаем имя скрипта без расширения
script_name_no_extension="${script_name%.*}"

echo "Устанавливаем $script_name_no_extension с именем $HOSTNAME"

# Проверяем, установлен ли пакет
if ! opkg list-installed | grep -q "^$PACKAGE_NAME"; then
    echo "Пакет $PACKAGE_NAME не установлен. Устанавливаем..."
    opkg update >/dev/null 2>&1  # Скрываем вывод команды update
    opkg install "$PACKAGE_NAME" >/dev/null 2>&1  # Скрываем вывод команды install
else
    echo "Пакет $PACKAGE_NAME уже установлен."
fi

echo "Начинаем настройку Mosquitto..."

# Получаем hostname
if [ -f /etc/hostname ]; then
    HOSTNAME=$(cat /etc/hostname)
elif command -v uname >/dev/null 2>&1; then
    HOSTNAME=$(uname -n)
elif command -v sysctl >/dev/null 2>&1; then
    HOSTNAME=$(sysctl kernel.hostname | awk '{print $2}')
else
    HOSTNAME="Xiaomi_Gateway_OpenWRT"
fi
DEFAULT_DEVICE_NAME=$(echo "$HOSTNAME" | sed 's/_\([0-9]*\)$//')

# Определяем текущий IP-адрес
CURRENT_IP=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
if [ -z "$CURRENT_IP" ]; then
	echo "Не удалось определить текущий IP-адрес."
	exit 1
fi

BASE_IP=$(echo "$CURRENT_IP" | awk -F'.' '{print $1"."$2"."$3}')
echo "Определен текущий диапазон IP: $BASE_IP.x (текущий IP: $CURRENT_IP)"

# Вычисляем начальный IP-адрес на основе текущего IP и номера устройства
if [ -n "$CURRENT_IP" ]; then
    CURRENT_LAST_OCTET=$(echo "$CURRENT_IP" | awk -F'.' '{print $4}')
else
    CURRENT_LAST_OCTET=1 # Значение по умолчанию
fi

# Получаем адрес MQTT-сервера из аргументов или интерактивно
MQTT_SERVER="${1:-localhost}"
DEVICE_NUMBER="${2:-0}" # Номер текущего устройства
DEVICE_COUNT="${3:-1}"  # Общее количество устройств

# Если адрес не передан через аргумент
if [ "$MQTT_SERVER" = "localhost" ]; then
    echo "Адрес MQTT-сервера не указан. Используем значение по умолчанию: $MQTT_SERVER."
else
    echo "Используем адрес MQTT-сервера: $MQTT_SERVER."
fi

# Если дополнительные параметры не переданы
if [ "$DEVICE_NUMBER" -eq 0 ]; then
	echo "Номер устройства не передан, считаем, что устройство одно, используем имя $DEFAULT_DEVICE_NAME):"
fi

# Если номер устройства не передан
if [ "$DEVICE_COUNT" -eq 1 ]; then
	echo "Количество устройств не передано, считаем, что устройство одно, используем имя $DEFAULT_DEVICE_NAME):"
fi


# Проверяем, существует ли файл конфигурации
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Файл конфигурации $CONFIG_FILE не найден. Создаём новый..."
    mkdir -p "$(dirname "$CONFIG_FILE")" # Создаем директорию, если она отсутствует
    touch "$CONFIG_FILE"
fi

# Массив для хранения адресов MQTT-серверов
MQTT_ADDRESSES=""

# Проверяем, есть ли другие устройства, кроме текущего
if [ "$DEVICE_COUNT" -gt 1 ]; then
    # Вычисляем IP-адреса устройств и исключаем текущее устройство
    for i in $(seq 1 "$DEVICE_COUNT"); do
        # Пропускаем текущее устройство
        if [ "$i" -eq "$DEVICE_NUMBER" ]; then
            continue
        fi
        TARGET_IP="$BASE_IP.$((CURRENT_LAST_OCTET - DEVICE_NUMBER + i))"
        MQTT_ADDRESSES="$MQTT_ADDRESSES, $TARGET_IP:1883"
    done
fi

# Функция для добавления главного моста в конфигурацию
add_main_server_bridge() {
# Добавляем MQTT Bridge, если адрес не равен localhost
	if [ "$MQTT_SERVER" != "localhost" ] && ! grep -q "^connection MQTT_Server$" "$CONFIG_FILE" && [ -s "$CONFIG_FILE" ]; then
		echo "Добавляем главный MQTT Server в $CONFIG_FILE..."
		cat <<EOF >> "$CONFIG_FILE"

# MQTT Bridge. Подключение к главному MQTT Server
connection MQTT_Server
address $MQTT_SERVER:1883$MQTT_ADDRESSES
round_robin false
remote_clientid $HOSTNAME
bridge_attempt_unsubscribe true
cleansession true
start_type automatic
try_private true
topic homeassistant/# out
topic lumi/# both
topic ble2mqtt/# both
topic zigbee2mqtt/# both
EOF
	elif [ "$MQTT_SERVER" = "localhost" ]; then
		echo "Конфигурация для MQTT Bridge не добавлена, так как адрес MQTT-сервера не задан."
	else
		echo "Конфигурация для MQTT Bridge не добавлена, так как MQTT_Server уже настроен или адрес MQTT-сервера равен 'localhost'."
	fi
}

# Функция для добавления мостов в конфигурацию
add_bridge() {
	local connection_name="$1"
	local ip="$2"
	if ! grep -q "^connection $connection_name$" "$CONFIG_FILE"; then
		echo "Добавляем мост для $connection_name с адресом $ip..."
		cat <<EOF >> "$CONFIG_FILE"

# MQTT Bridge. Подключение к $connection_name
connection $connection_name
address $ip:1883
bridge_attempt_unsubscribe true
cleansession true
start_type automatic
allow_anonymous true
try_private true
topic # both 0 "" ""
EOF
	else
		echo "Подключение к $connection_name уже настроено."
	fi
}

add_zeroconf() {
	if ! grep -q "^zeroconf true$" "$CONFIG_FILE"; then
		echo "Добавляем zeroconf с адресом $CURRENT_IP..."
		cat <<EOF >> "$CONFIG_FILE"

zeroconf true
zeroconf service_name mosquitto
zeroconf hostname $CURRENT_IP
zeroconf port 1883
EOF
	else
		echo "Подключение zeroconf уже настроено."
	fi
}

##################################################

# Проверяем, есть ли строка listener 1883
if ! grep -q "^listener 1883$" "$CONFIG_FILE"; then
    echo "Добавляем 'listener 1883' в $CONFIG_FILE..."
    echo -e "\n\nlistener 1883" >> "$CONFIG_FILE"
else
    echo "'listener 1883' уже существует в $CONFIG_FILE."
fi

# Проверяем, есть ли строка allow_anonymous true
if ! grep -q "^allow_anonymous true$" "$CONFIG_FILE"; then
    echo "Добавляем 'allow_anonymous true' в $CONFIG_FILE..."
    echo "allow_anonymous true" >> "$CONFIG_FILE"
else
    echo "'allow_anonymous true' уже существует в $CONFIG_FILE."
fi

add_zeroconf

add_main_server_bridge

# Настраиваем мосты для всех устройств, кроме текущего
if [ "$DEVICE_COUNT" -gt 1 ]; then
    echo "Настраиваем мосты для устройств в сети, кроме текущего ($DEVICE_NUMBER)..."
    for i in $(seq 1 "$DEVICE_COUNT"); do
        # Пропускаем настройку для текущего устройства
        if [ "$i" -eq "$DEVICE_NUMBER" ]; then
            # echo "Пропускаем настройку моста для текущего устройства ($HOSTNAME, $CURRENT_IP)."
            continue
        fi

        TARGET_IP="$BASE_IP.$((CURRENT_LAST_OCTET + i - DEVICE_NUMBER))"
        DEVICE_NAME="${DEFAULT_DEVICE_NAME}_${i}"
        add_bridge "$DEVICE_NAME" "$TARGET_IP"
    done
else
    echo "Количество устройств равно 1 или не задано. Мосты не настроены."
fi

# Перезапуск службы Mosquitto
if command -v systemctl > /dev/null; then
    echo "Перезапускаем службу Mosquitto..."
    systemctl restart mosquitto
elif command -v /etc/init.d/mosquitto > /dev/null; then
    echo "Перезапускаем службу Mosquitto (init.d)..."
    /etc/init.d/mosquitto restart
else
    echo "Не удалось найти способ перезапуска службы Mosquitto."
fi

echo "Настройка Mosquitto завершена."


