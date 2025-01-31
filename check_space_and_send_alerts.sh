#!/bin/bash

# Конфигурационные параметры
SNMP_COMMUNITY="public"
THRESHOLD=80             # Порог использования в процентах
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN"  # Токен Telegram бота
CHAT_ID="YOUR_CHAT_ID"              # Идентификатор чата
HOSTS=("192.168.1.232" "192.168.1.233")  # Список хостов
INCLUDE_PARTITIONS=("/" "/tmp" "/var/log")  # Включаемые разделы

# Проверка конфигурации Telegram
check_telegram_config() {
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        echo "Ошибка конфигурации: Telegram бот токен и/или Chat ID не заданы!"
        return 1
    fi
    return 0
}

# Функция отправки сообщения в Telegram
send_telegram_alert() {
    local message="$1"
    curl -s -G \
        --data-urlencode "text=$message" \
        "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data "chat_id=$CHAT_ID" &>/dev/null
}

# Основной цикл проверки
for REMOTE_IP in "${HOSTS[@]}"; do
    echo "Опрашиваю хост $REMOTE_IP..."
    
    PARTITIONS=$(snmpwalk -v 2c -c $SNMP_COMMUNITY $REMOTE_IP .1.3.6.1.2.1.25.2.3.1.3 2>/dev/null | 
                grep STRING | awk -F '.' '{print $NF}' | awk '{print $1}')

    if [ -z "$PARTITIONS" ]; then
        echo "Ошибка: невозможно получить список разделов с хоста $REMOTE_IP."
        continue
    fi

    for INDEX in $PARTITIONS; do
        DESCRIPTION=$(snmpget -v 2c -c $SNMP_COMMUNITY $REMOTE_IP .1.3.6.1.2.1.25.2.3.1.3.$INDEX 2>/dev/null | 
                     awk -F ': ' '{print $2}' | tr -d '"')

        # Проверка на включение в список нужных разделов
        [[ " ${INCLUDE_PARTITIONS[*]} " != *" $DESCRIPTION "* ]] && continue

        SIZE=$(snmpget -v 2c -c $SNMP_COMMUNITY $REMOTE_IP .1.3.6.1.2.1.25.2.3.1.5.$INDEX 2>/dev/null | awk '{print $NF}')
        USED=$(snmpget -v 2c -c $SNMP_COMMUNITY $REMOTE_IP .1.3.6.1.2.1.25.2.3.1.6.$INDEX 2>/dev/null | awk '{print $NF}')

        if [ -n "$SIZE" ] && [ "$SIZE" -ne 0 ] 2>/dev/null; then
            USAGE=$(( USED * 100 / SIZE ))
            echo "Раздел: $DESCRIPTION, Занято: $USAGE% (Хост: $REMOTE_IP)"

            # Проверка порога и отправка уведомления
            if [ "$USAGE" -ge "$THRESHOLD" ]; then
                alert_msg="Хост: $REMOTE_IP
Раздел: $DESCRIPTION
Использование: $USAGE% (Порог: $THRESHOLD%)"

                if check_telegram_config; then
                    send_telegram_alert "$alert_msg"
                    echo "Уведомление отправлено в Telegram"
                fi
            fi
        else
            echo "Ошибка получения данных для раздела $DESCRIPTION (Хост: $REMOTE_IP)"
        fi
    done
    echo "--------------------------"
done
