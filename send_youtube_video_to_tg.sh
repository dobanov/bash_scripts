#!/bin/bash

# Проверяем, что передан хотя бы один аргумент
if [[ -z "$1" ]]; then
    echo "Использование:"
    echo "  $0 <URL>               # Загрузить одно видео"
    echo "  $0 <file.txt>          # Загрузить видео из файла с URL"
    exit 1
fi

# Максимальный размер файла в байтах (50 МБ = 52428800 байт)
MAX_FILE_SIZE=$((50 * 1024 * 1024))
PART_SIZE=$((49 * 1024 * 1024))

# Функция для разбиения видео с сохранением заголовков
split_video() {
    local input_file="$1"
    local output_prefix="$2"
    local max_part_size=49000000  # Максимальный размер части (байты)
    local duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input_file")

    echo "Общая длительность видео: $duration секунд."

    # Расчёт времени для части
    local approx_part_time=$(bc <<< "scale=2; $duration * $max_part_size / $(stat --format=%s "$input_file")")
    local part_time=$(printf "%.0f" "$approx_part_time")

    if [[ $part_time -lt 10 ]]; then
        part_time=10  # Минимальная длина части в секундах
    fi

    echo "Длительность одной части: $part_time секунд."

    # Используем ffmpeg для разбиения на части по времени
    ffmpeg -hide_banner -i "$input_file" -c copy -map 0 -segment_time "$part_time" -f segment -reset_timestamps 1 -movflags +frag_keyframe+empty_moov "${output_prefix}_part_%03d.mp4"
}


# Функция для загрузки видео и отправки
split_and_send() {
    local file="$1"
    local original_url="$2"

    # Проверяем размер файла
    local file_size=$(stat --format=%s "$file")
    if [[ $file_size -le $MAX_FILE_SIZE ]]; then
        # Если файл меньше 50 МБ, отправляем его напрямую
        echo "Отправка файла $file (размер: $file_size байт)"
        curl -F "video=@./$output_file" "https://api.telegram.org/bot<BOT_TOKEN>/sendVideo?chat_id=<CHAT_ID>&caption=$url&supports_streaming=true"
        return $?
    fi

    # Если файл больше 50 МБ, разбиваем на части с сохранением заголовков
    local output_prefix="${file%.*}"
    split_video "$file" "$output_prefix"

    # Отправляем каждую часть
    for part in ${output_prefix}_part_*.mp4; do
        echo "Отправка части: $part"
        caption=$(echo "$original_url (часть $(basename "$part"))" | jq -sRr @uri)
        curl -F "video=@./$part" "https://api.telegram.org/bot<BOT_TOKEN>/sendVideo?chat_id=<CHAT_ID>&caption=$caption&supports_streaming=true"
        if [[ $? -ne 0 ]]; then
            echo "Ошибка отправки части: $part"
        else
            echo "Часть $part успешно отправлена."
        fi
    done

    # Удаляем части после отправки
    rm -f ${output_prefix}_part_*.mp4
}

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

    # Проверяем размер и отправляем (с разбиением, если необходимо)
    split_and_send "$output_file" "$url"

    # Удаляем оригинальный файл после обработки
    rm -f "$output_file"
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

