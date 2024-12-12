#!/bin/bash

# Проверяем, что передан хотя бы один аргумент
if [[ -z "$1" ]]; then
    echo "Использование:"
    echo "  $0 <URL>               # Загрузить одно видео"
    echo "  $0 <file.txt>          # Загрузить видео из файла с URL"
    exit 1
fi

# Функция для загрузки видео и отправки
download_and_send() {
    local url="$1"
    local output_file="video.mp4"
    echo "Начинаем обработку URL: $url"

    # Загружаем видео с помощью yt-dlp
    yt-dlp -f "best[height<=720][ext=mp4]" -o "video.%(ext)s" --force-overwrites "$url"
    if [[ $? -ne 0 ]]; then
        echo "Ошибка загрузки видео для URL: $url"
        return 1
    fi

    # Проверяем, что файл был успешно скачан
    if [[ ! -f "$output_file" ]]; then
        echo "Ошибка: файл $output_file не найден после загрузки."
        return 1
    fi

    # Отправляем видео через Telegram Bot API с помощью curl
    echo "Отправка видео для URL: $url"
    curl -F "video=@./$output_file" "https://api.telegram.org/bot<BOT_TOKEN>/sendVideo?chat_id=<CHAT_ID>&caption=$url&supports_streaming=true"
    if [[ $? -ne 0 ]]; then
        echo "Ошибка отправки видео для URL: $url"
        return 1
    fi

    echo "Успешно обработан URL: $url"
}

# Проверяем аргумент
input="$1"

if [[ -f "$input" && "${input##*.}" == "txt" ]]; then
    # Если аргумент — это файл с расширением .txt
    echo "Обработка файла с URL: $input"

    # Считываем URL из файла и обрабатываем каждый
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue # Пропуск пустых строк
        download_and_send "$url"
    done < "$input"

else
    # Если аргумент — это, скорее всего, URL
    echo "Обработка одиночного URL: $input"
    download_and_send "$input"
fi
