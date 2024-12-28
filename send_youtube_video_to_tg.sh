#!/bin/bash

# Настройки Telegram
TOKEN="Token"
CHAT_ID="Chat_ID"
API_URL="https://api.telegram.org/bot${TOKEN}/sendVideo"
MAX_FILE_SIZE=$((52400000)) # 50 МБ в байтах

# Проверяем, что передан хотя бы один аргумент
if [[ -z "$1" ]]; then
    echo "Использование:"
    echo "  $0 <URL>               # Загрузить одно видео"
    echo "  $0 <file.txt>          # Загрузить видео из файла с URL"
    exit 1
fi

# Функция для проверки корректности параметра
validate_input() {
    local input="$1"

    if [[ -f "$input" && "${input##*.}" == "txt" ]]; then
        echo "Параметр '$input' распознан как текстовый файл."
        return 0
    elif [[ "$input" =~ ^https://www\.youtube\.com/watch\?v= ]]; then
        echo "Параметр '$input' распознан как валидный YouTube URL."
        return 0
    else
        echo "Ошибка: Параметр '$input' не является ни валидным YouTube URL, ни текстовым файлом с URL."
        echo "Использование:"
        echo "  $0 <URL>               # Загрузить одно видео"
        echo "  $0 <file.txt>          # Загрузить видео из файла с URL"
        exit 1
    fi
}

# Функция для разбиения видео на части
split_video() {
    local input_file="$1"
    local output_prefix="$2"
    local max_part_size=49000000 # Чуть меньше 50 МБ, чтобы учесть метаданные

    # Получаем общую длительность видео
    local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file")
    local total_size=$(stat --format=%s "$input_file")

    # Рассчитываем приблизительное время для одной части
    local approx_part_time=$(echo "$duration * $max_part_size / $total_size" | bc -l)
    local part_time=$(printf "%.0f" "$approx_part_time")

    # Если рассчитанное время слишком маленькое, задаем минимальное значение (10 секунд)
    if [[ $part_time -lt 10 ]]; then
        part_time=10
    fi

    # Разбиваем видео на части
    ffmpeg -i "$input_file" -c copy -map 0 -segment_time "$part_time" -f segment -reset_timestamps 1 "${output_prefix}_%03d.mp4" >/dev/null 2>&1

    echo "Видео успешно разбито на части."
}

# Функция для URL-кодирования строки
urlencode() {
    local encoded=""
    local char
    for (( i=0; i<${#1}; i++ )); do
        char="${1:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+="$char" ;;
            *) encoded+=$(printf '%%%02X' "'$char") ;;
        esac
    done
    echo "$encoded"
}

# Отправляем части с корректной кодировкой caption
send_video() {
    local file="$1"
    local caption="$2"
    local encoded_caption
    encoded_caption=$(urlencode "$caption")
    curl -F "video=@${file}" "${API_URL}?chat_id=${CHAT_ID}&caption=${encoded_caption}&supports_streaming=true"
}

# Функция для загрузки видео и отправки
download_and_send() {
    local url="$1"
    local output_file="video.mp4"
    echo "Начинаем обработку URL: $url"

    # Загружаем видео с помощью yt-dlp
    yt-dlp -f "bv*[height<=720]+ba/best" --merge-output-format mp4 -o "$output_file" --force-overwrites "$url"
    if [[ $? -ne 0 ]]; then
        echo "Ошибка загрузки видео для URL: $url"
        return 1
    fi

    # Проверяем, что файл был успешно скачан
    if [[ ! -f "$output_file" ]]; then
        echo "Ошибка: файл $output_file не найден после загрузки."
        return 1
    fi

    # Проверяем размер файла
    local file_size=$(stat --format=%s "$output_file")
    if [[ $file_size -le $MAX_FILE_SIZE ]]; then
        # Отправляем файл целиком
        echo "Отправка видео для URL: $url"
        send_video "$output_file" "$url"
        if [[ $? -ne 0 ]]; then
            echo "Ошибка отправки видео для URL: $url"
            return 1
        fi
    else
        # Если файл больше 50 МБ, разбиваем его на части
        echo "Видео превышает 50 МБ. Разбиваем на части..."
        split_video "$output_file" "video_part"
        for part in video_part_*.mp4; do
            echo "Отправка части $part для URL: $url"
            send_video "$part" "$url (часть $part)"
            if [[ $? -ne 0 ]]; then
                echo "Ошибка отправки части $part для URL: $url"
                return 1
            fi
            rm -f "$part" # Удаляем отправленную часть
        done
    fi

    # Удаляем исходное видео
    rm -f "$output_file"
    echo "Успешно обработан URL: $url"
}

# Проверяем аргумент
input="$1"

# Выполняем проверку переданного параметра
validate_input "$input"

if [[ -f "$input" && "${input##*.}" == "txt" ]]; then
    # Если аргумент — это файл с расширением .txt
    echo "Обработка файла с URL: $input"

    # Считываем URL из файла и обрабатываем каждый
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue # Пропуск пустых строк
        download_and_send "$url"
    done < "$input"

else
    # Если аргумент — это валидный URL
    echo "Обработка одиночного URL: $input"
    download_and_send "$input"
fi
