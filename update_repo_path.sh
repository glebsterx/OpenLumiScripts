#!/bin/sh

# Получение версии OpenWrt
OPENWRT_VERSION=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)

# Извлечение основной версии (например, 21 из 21.02.0)
MAIN_VERSION=$(echo "$OPENWRT_VERSION" | cut -d '.' -f 1)

# Сравнение основной версии
if [ "$MAIN_VERSION" -lt 23 ]; then
    echo "Версия OpenWrt ($OPENWRT_VERSION) < 23. Вносим изменения в distfeeds.conf..."
    sed -i 's/releases/archive/' /etc/opkg/distfeeds.conf
else
    echo "Версия OpenWrt ($OPENWRT_VERSION) >= 23. Изменения не требуются."
fi
