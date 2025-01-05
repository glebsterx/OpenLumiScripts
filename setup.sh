#!/bin/sh

# Определение директории установки
INSTALL_DIR=$(cd "$(dirname "$0")" && pwd)
COMPONENTS=""
SELECTED_COMPONENTS=""
DEFAULT_MQTT_SERVER="localhost"
UPSTREAM_MQTT_SERVER="192.168.0.3"
MQTT_SERVER=""
HOSTNAME=$(uname -n)
DEFAULT_HOSTNAME="Xiaomi_Gateway_OpenWRT"
NEW_HOSTNAME=""

# Определяем текущий IP-адрес
CURRENT_IP=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
if [ -z "$CURRENT_IP" ]; then
	echo "Не удалось определить текущий IP-адрес."
	exit 1
fi

# Вычисляем начальный IP-адрес на основе текущего IP и номера устройства
if [ -n "$CURRENT_IP" ]; then
    CURRENT_LAST_OCTET=$(echo "$CURRENT_IP" | awk -F'.' '{print $4}')
	# Получаем последнюю цифру последнего октета
	LAST_DIGIT=$(echo "$CURRENT_LAST_OCTET" | awk '{print substr($0, length($0), 1)}')
fi
DEFAULT_HOSTNAME="${DEFAULT_HOSTNAME}_${LAST_DIGIT}"

read -p "Текущее имя устройства: $HOSTNAME. Введите новое имя устройства (по умолчанию $DEFAULT_HOSTNAME): " NEW_HOSTNAME
NEW_HOSTNAME=${NEW_HOSTNAME:-$DEFAULT_HOSTNAME}

# Изменяем /etc/config/system
if grep -q "option hostname" /etc/config/system; then
    sed -i "s/option hostname.*/option hostname '$NEW_HOSTNAME'/" /etc/config/system
else
    echo "Добавляем строку hostname в /etc/config/system..."
    echo "config system" >> /etc/config/system
    echo "    option hostname '$NEW_HOSTNAME'" >> /etc/config/system
fi
# Применяем изменения
/etc/init.d/system reload

echo "Имя устройства успешно изменено на $NEW_HOSTNAME."

# Генерация списка компонентов на основе файлов .sh
generate_components_list() {
    for script in "$INSTALL_DIR"/*.sh; do
        script_name=$(basename "$script" .sh)
        case "$script_name" in
            "start" | "setup" | "update_repo_path")
                # Пропускаем setup.sh и update_repo_path.sh
                continue
                ;;
            *)
                COMPONENTS="$COMPONENTS $script_name"
                ;;
        esac
    done
}

# Функция для отображения списка компонентов с выбором
choose_components() {
    echo "Выберите компоненты для установки (введите номера через пробел):"
    idx=1
    for component in $COMPONENTS; do
        echo "$idx) $component"
        idx=$((idx + 1))
    done

    # read -p "Ваш выбор: " choices
    # idx=1
    # for component in $COMPONENTS; do
        # for choice in $choices; do
            # if [ "$choice" -eq "$idx" ]; then
                # SELECTED_COMPONENTS="$SELECTED_COMPONENTS $component"
            # fi
        # done
        # idx=$((idx + 1))
    # done
		
	read -p "Ваш выбор (по умолчанию выбраны все комопоненты кроме ble2mqtt, lumimqttd): " choices
	# Если choices пусто, выбираем все компоненты
	if [ -z "$choices" ]; then
		SELECTED_COMPONENTS=$(echo "$COMPONENTS" | tr ' ' '\n' | grep -v '^ble2mqtt$' | grep -v '^lumimqttd$' | tr '\n' ' ')
	else
		for choice in $choices; do
			if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$(echo $COMPONENTS | wc -w)" ]; then
				SELECTED_COMPONENTS="$SELECTED_COMPONENTS $(echo $COMPONENTS | awk -v n="$choice" '{print $n}')"
			else
				echo "Неверный выбор: $choice"
			fi
		done
	fi
	
}

# Проверка и запуск update_repo_path.sh

update_repo_path() {
	echo "Обновление адресов репозиториев..."
	if [ -f "$INSTALL_DIR/update_repo_path.sh" ]; then
		echo "Запускаем update_repo_path.sh..."
		sh "$INSTALL_DIR/update_repo_path.sh"
	else
		echo "Скрипт update_repo_path.sh не найден!"
		exit 1
	fi
}

# Генерация списка компонентов
generate_components_list

# Проверяем, есть ли доступные компоненты
if [ -z "$COMPONENTS" ]; then
    echo "Нет доступных компонентов для установки."
    exit 1
fi

# Выбор компонентов для установки
choose_components

# Если mosquitto выбран для установки
mosquitto_selected=false
for component in $SELECTED_COMPONENTS; do
    if [ "$component" = "mosquitto" ]; then
        mosquitto_selected=true
        break
    fi
done

read -p "Введите адрес внешнего MQTT сервера (например, $UPSTREAM_MQTT_SERVER): " UPSTREAM_MQTT_SERVER
UPSTREAM_MQTT_SERVER=${UPSTREAM_MQTT_SERVER:-$DEFAULT_MQTT_SERVER}
# Если адрес внешнего сервера - localhost
if [ "$UPSTREAM_MQTT_SERVER" = "localhost" ]; then
	echo "Адрес внешнего MQTT-сервера не указан. Используем значение по умолчанию: $DEFAULT_MQTT_SERVER."
	if [ "$mosquitto_selected" = "true" ]; then
		echo "Настройка MQTT будет произведена на локальный сервер".
		MQTT_SERVER=$UPSTREAM_MQTT_SERVER
	else
		echo ">>> Нужно выбрать внешний сервер или установить Mosquitto! <<<"
		MQTT_SERVER="localhost"
		read -p "Устанавливаем локальный Mosquitto? [y/N]: " use_mosquitto
		case "$use_mosquitto" in
			[yY]*)
				SELECTED_COMPONENTS="mosquitto $SELECTED_COMPONENTS"
				echo "Будет установлен локальный MQTT-сервер ($MQTT_SERVER).".
				;;
			*)
				# пока е
				echo "Адрес внешнего MQTT-сервера не указан. Локальный можно установить позже вручную.".
				;;
		esac
	fi
else
	read -p "Использовать внешний MQTT сервер ($UPSTREAM_MQTT_SERVER) для настройки других пакетов? [y/N]: " use_local
	case "$use_local" in
		[yY]*)
			MQTT_SERVER=$UPSTREAM_MQTT_SERVER
			echo "Настройка пакетов будет произведена на внешний сервер ($UPSTREAM_MQTT_SERVER).".
			;;
		*)
			MQTT_SERVER="localhost"
			echo "Настройка пакетов будет произведена на локальный сервер ($MQTT_SERVER).".
			;;
	esac
fi

if [ "$mosquitto_selected" = "true" ]; then
	read -p "Введите номер устройства: " DEVICE_NUMBER
    read -p "Введите количество устройств: " DEVICE_COUNT
	DEVICE_NUMBER="${DEVICE_NUMBER:-0}" # Номер текущего устройства
	DEVICE_COUNT="${DEVICE_COUNT:-1}"  # Общее количество устройств
	# Если дополнительные параметры не переданы
	if [ "$DEVICE_NUMBER" -eq 0 ]; then
		echo "Номер устройства не передан, считаем, что устройство одно, используем имя $DEFAULT_DEVICE_NAME):"
	fi
	# Если номер устройства не передан
	if [ "$DEVICE_COUNT" -eq 1 ]; then
		echo "Количество устройств не передано, считаем, что устройство одно, используем имя $DEFAULT_DEVICE_NAME):"
	fi
	
fi

# Обновляем пути к репозиториям
update_repo_path

# Установка выбранных компонентов
for component in $SELECTED_COMPONENTS; do
    INSTALL_SCRIPT="$INSTALL_DIR/${component}.sh"
    if [ -f "$INSTALL_SCRIPT" ]; then
        echo "Устанавливаем $component..."
        chmod +x "$INSTALL_SCRIPT"
        if [ "$component" = "mosquitto" ]; then
            sh "$INSTALL_SCRIPT" "$UPSTREAM_MQTT_SERVER" "$DEVICE_NUMBER" "$DEVICE_COUNT"
        else
            sh "$INSTALL_SCRIPT" "$MQTT_SERVER"
        fi
    else
        echo "Скрипт установки для $component не найден!"
    fi
done
echo "Установка завершена!"
