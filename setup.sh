#!/bin/sh

# Определение директории установки
INSTALL_DIR=$(cd "$(dirname "$0")" && pwd)
COMPONENTS=""
SELECTED_COMPONENTS=""
DEFAULT_MQTT_SERVER="localhost"
MQTT_SERVER=""
HOSTNAME=$(uname -n)
DEFAULT_HOSTNAME="Xiaomi_Gateway_OpenWRT"
NEW_HOSTNAME=""

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
		
	read -p "Ваш выбор (по умолчанию выбраны все комопоненты кроме lumimqttd): " choices
	# Если choices пусто, выбираем все компоненты
	if [ -z "$choices" ]; then
		SELECTED_COMPONENTS=$(echo "$COMPONENTS" | tr ' ' '\n' | grep -v '^lumimqttd$' | tr '\n' ' ')
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

read -p "Введите адрес внешнего MQTT сервера (например, $DEFAULT_MQTT_SERVER): " MQTT_SERVER
MQTT_SERVER=${MQTT_SERVER:-$DEFAULT_MQTT_SERVER}
# Если адрес внешнего сервера - localhost
if [ "$MQTT_SERVER" = "localhost" ]; then
	echo "Адрес MQTT-сервера не указан. Используем значение по умолчанию: $DEFAULT_MQTT_SERVER."
else
	echo "Используем адрес внешнего MQTT-сервера: $MQTT_SERVER."
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
            sh "$INSTALL_SCRIPT" "$MQTT_SERVER" "$DEVICE_NUMBER" "$DEVICE_COUNT"
        else
            sh "$INSTALL_SCRIPT" "$MQTT_SERVER"
        fi
    else
        echo "Скрипт установки для $component не найден!"
    fi
done
echo "Установка завершена!"
