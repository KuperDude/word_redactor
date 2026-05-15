#!/bin/bash

TEMPLATE_DIR="/app/templates"
OUTPUT_DIR="/app/outputs"
mkdir -p "$TEMPLATE_DIR" "$OUTPUT_DIR"

declare -a APP_TITLES
declare -a APP_TEXTS
declare -a APP_PAGES

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&apos;}"
    printf "%s" "$s"
}

select_template() {
    echo "Выберите файл шаблона (.docx):" >&2
    local templates=()
    if [ -d "$TEMPLATE_DIR" ]; then
        while IFS= read -r file; do
            templates+=("$file")
        done < <(find "$TEMPLATE_DIR" -maxdepth 1 -name "*.docx" -type f | sort)
    fi
    if [ ${#templates[@]} -eq 0 ]; then
        echo "Ошибка: Нет .docx файлов в $TEMPLATE_DIR" >&2
        exit 1
    fi
    for i in "${!templates[@]}"; do
        echo "  $((i+1))) $(basename "${templates[$i]}")" >&2
    done
    read -p "Выберите номер [1-${#templates[@]}]: " choice >&2
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#templates[@]} ]; then
        TEMPLATE_FILE="${templates[$((choice-1))]}"
    else
        echo "Неверный выбор!" >&2
        exit 1
    fi
}

input_applications() {
    echo >&2
    read -p "Сколько приложений добавить? (0 если без): " app_count >&2
    if ! [[ "$app_count" =~ ^[0-9]+$ ]]; then
        app_count=0
    fi
    if [ "$app_count" -eq 0 ]; then
        return
    fi
    for ((i=1; i<=app_count; i++)); do
        echo >&2
        echo "--- Приложение $i ---" >&2
        read -p "Заголовок: " title >&2
        APP_TITLES+=("$title")
        read -p "Количество страниц (ENTER если не нужно): " pages >&2
        APP_PAGES+=("$pages")
        echo "Текст приложения (пустая строка - конец):" >&2
        local text=""
        local line_num=1
        while true; do
            read -p "$line_num> " line >&2
            if [ -z "$line" ]; then
                break
            fi
            text="${text}${line}\n"
            ((line_num++))
        done
        APP_TEXTS+=("$text")
    done
}

extract_placeholders() {
    local docx_file="$1"
    local temp_dir=$(mktemp -d)
    unzip -q "$docx_file" -d "$temp_dir" 2>/dev/null
    local placeholders=()
    if [ -f "$temp_dir/word/document.xml" ]; then
        while IFS= read -r placeholder; do
            [ -n "$placeholder" ] && placeholders+=("$placeholder")
        done < <(grep -o '{APPENDICES}\|{[^}]*}' "$temp_dir/word/document.xml" | sort -u)
    fi
    rm -rf "$temp_dir"
    printf '%s\n' "${placeholders[@]}" | sort -u
}

input_placeholder_data() {
    local placeholders=("$@")
    declare -gA placeholder_values
    echo >&2
    for placeholder in "${placeholders[@]}"; do
        if [ "$placeholder" == "{APPENDICES}" ]; then
            continue
        fi
        local clean_name=$(echo "$placeholder" | sed 's/[{}]//g')
        local display_name=$(echo "$clean_name" | sed 's/_/ /g' | tr '[:upper:]' '[:lower:]' | sed 's/\b\(.\)/\u\1/g')
        read -p "${display_name} (${placeholder}): " value >&2
        if [ -z "$value" ]; then
            value=" "
        fi
        placeholder_values["$placeholder"]="$value"
    done
}

generate_appendices_bodies() {
    local bodies=""
    for ((i=0; i<${#APP_TITLES[@]}; i++)); do
        local num=$((i+1))
        local title="${APP_TITLES[$i]}"
        local text="${APP_TEXTS[$i]}"
        bodies="$bodies<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
        bodies="$bodies<w:p><w:pPr><w:jc w:val=\"right\"/></w:pPr><w:r><w:t>Приложение $num</w:t></w:r></w:p>"
        bodies="$bodies<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>$(xml_escape "$title")</w:t></w:r></w:p>"
        IFS=$'\n' read -rd '' -a lines <<< "$text"
        for line in "${lines[@]}"; do
            [ -n "$line" ] && bodies="$bodies<w:p><w:r><w:t>$(xml_escape "$line")</w:t></w:r></w:p>"
        done
    done
    echo "$bodies"
}

replace_appendices_list() {
    local document_xml="$1"
    if [ ${#APP_TITLES[@]} -eq 0 ]; then
        sed -i 's/{APPENDICES}//g' "$document_xml"
        return
    fi
    local header_text="Приложения:"
    [ ${#APP_TITLES[@]} -eq 1 ] && header_text="Приложение:"
    local items_xml='<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>'$(xml_escape "$header_text")'</w:t></w:r></w:p>'
    for ((i=0; i<${#APP_TITLES[@]}; i++)); do
        local num=$((i+1))
        local title="${APP_TITLES[$i]}"
        local pages="${APP_PAGES[$i]}"
        local line="${num}. ${title}"
        [ -n "$pages" ] && [ "$pages" != "" ] && line="${line} на ${pages} л."
        items_xml="$items_xml"$'\n'"<w:p><w:r><w:t>$(xml_escape "$line")</w:t></w:r></w:p>"
    done
    local items_escaped=$(echo "$items_xml" | sed ':a;N;$!ba;s/\n/\\n/g')
    if command -v perl &>/dev/null; then
        perl -i -0pe 's#<w:p>(?:(?!</w:p>).)*{APPENDICES}(?:(?!</w:p>).)*</w:p>#'"$items_escaped"'#gs' "$document_xml"
    elif sed --version 2>/dev/null | grep -q GNU; then
        sed -i -z 's#<w:p>[^<]*{APPENDICES}[^<]*</w:p>#'"$items_escaped"'#g' "$document_xml"
    else
        echo "Ошибка: нужен perl или GNU sed" >&2
        exit 1
    fi
}

append_app_bodies() {
    local document_xml="$1"
    local bodies_xml=$(generate_appendices_bodies)
    if grep -q "</w:body>" "$document_xml"; then
        sed -i "s|</w:body>|${bodies_xml}\n</w:body>|" "$document_xml"
    else
        echo "Ошибка: не найден </w:body>" >&2
        exit 1
    fi
}

build_docx() {
    local output_filename="$1"
    local temp_dir=$(mktemp -d)
    unzip -q "$TEMPLATE_FILE" -d "$temp_dir" 2>/dev/null || { rm -rf "$temp_dir"; return 1; }
    local document_xml="$temp_dir/word/document.xml"

    for placeholder in "${!placeholder_values[@]}"; do
        if [ "$placeholder" != "{APPENDICES}" ]; then
            local value="${placeholder_values[$placeholder]}"
            local escaped_value=$(xml_escape "$value")
            sed -i "s|${placeholder}|${escaped_value}|g" "$document_xml"
        fi
    done

    replace_appendices_list "$document_xml"
    if [ ${#APP_TITLES[@]} -gt 0 ]; then
        append_app_bodies "$document_xml"
    fi

    local final_path="$OUTPUT_DIR/$output_filename"
    (cd "$temp_dir" && zip -qr "$final_path" .) || { rm -rf "$temp_dir"; return 1; }
    rm -rf "$temp_dir"
    echo "$final_path"
}

# -------------------------------------------------------------------
# Основной блок
# -------------------------------------------------------------------
select_template
mapfile -t placeholders < <(extract_placeholders "$TEMPLATE_FILE")
input_applications
input_placeholder_data "${placeholders[@]}"
read -p "Имя выходного файла (без расширения): " out_name >&2
[ -z "$out_name" ] && out_name="output_$(date +%Y%m%d_%H%M%S)"
out_name="${out_name}.docx"
final_file=$(build_docx "$out_name")
if [ $? -eq 0 ]; then
    echo "$final_file"
else
    echo "Ошибка генерации" >&2
    exit 1
fi
