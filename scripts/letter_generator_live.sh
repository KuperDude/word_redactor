#!/bin/bash
# letter_generator_live.sh – generate DOCX with preview update after each action

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
OUTPUT_DIR="$SCRIPT_DIR/../outputs"
LIVE_FILE="$OUTPUT_DIR/preview.docx"

mkdir -p "$TEMPLATE_DIR" "$OUTPUT_DIR"

declare -a APP_TITLES
declare -a APP_TEXTS
declare -a APP_PAGES
declare -A placeholder_values

# -------------------------------------------------------------------
# Helper functions (unchanged)
# -------------------------------------------------------------------
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
    echo "Select template file (.docx):" >&2
    local templates=()
    if [ -d "$TEMPLATE_DIR" ]; then
        while IFS= read -r file; do
            templates+=("$file")
        done < <(find "$TEMPLATE_DIR" -maxdepth 1 -name "*.docx" -type f | sort)
    fi
    if [ ${#templates[@]} -eq 0 ]; then
        echo "Error: No .docx files in $TEMPLATE_DIR" >&2
        exit 1
    fi
    for i in "${!templates[@]}"; do
        echo "  $((i+1))) $(basename "${templates[$i]}")" >&2
    done
    read -p "Select number [1-${#templates[@]}]: " choice >&2
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#templates[@]} ]; then
        TEMPLATE_FILE="${templates[$((choice-1))]}"
    else
        echo "Invalid choice!" >&2
        exit 1
    fi
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

generate_appendices_bodies() {
    local bodies=""
    for ((i=0; i<${#APP_TITLES[@]}; i++)); do
        local num=$((i+1))
        local title="${APP_TITLES[$i]}"
        local text="${APP_TEXTS[$i]}"
        bodies="$bodies<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
        bodies="$bodies<w:p><w:pPr><w:jc w:val=\"right\"/></w:pPr><w:r><w:t>Appendix $num</w:t></w:r></w:p>"
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
    local header_text="Appendices:"
    [ ${#APP_TITLES[@]} -eq 1 ] && header_text="Appendix:"
    local items_xml='<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>'$(xml_escape "$header_text")'</w:t></w:r></w:p>'
    for ((i=0; i<${#APP_TITLES[@]}; i++)); do
        local num=$((i+1))
        local title="${APP_TITLES[$i]}"
        local pages="${APP_PAGES[$i]}"
        local line="${num}. ${title}"
        [ -n "$pages" ] && [ "$pages" != "" ] && line="${line} on ${pages} p."
        items_xml="$items_xml"$'\n'"<w:p><w:r><w:t>$(xml_escape "$line")</w:t></w:r></w:p>"
    done
    local items_escaped=$(echo "$items_xml" | sed ':a;N;$!ba;s/\n/\\n/g')
    if command -v perl &>/dev/null; then
        perl -i -0pe 's#<w:p>(?:(?!</w:p>).)*{APPENDICES}(?:(?!</w:p>).)*</w:p>#'"$items_escaped"'#gs' "$document_xml"
    elif sed --version 2>/dev/null | grep -q GNU; then
        sed -i -z 's#<w:p>[^<]*{APPENDICES}[^<]*</w:p>#'"$items_escaped"'#g' "$document_xml"
    else
        echo "Error: need perl or GNU sed" >&2
        exit 1
    fi
}

append_app_bodies() {
    local document_xml="$1"
    local bodies_xml=$(generate_appendices_bodies)
    if grep -q "</w:body>" "$document_xml"; then
        sed -i "s|</w:body>|${bodies_xml}\n</w:body>|" "$document_xml"
    else
        echo "Error: </w:body> not found" >&2
        exit 1
    fi
}

# --------------------------------------------------------------
# Generate to given file
# --------------------------------------------------------------
build_docx_to_file() {
    local output_file="$1"
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

    (cd "$temp_dir" && zip -qr "$output_file" .) || { rm -rf "$temp_dir"; return 1; }
    rm -rf "$temp_dir"
    echo "Generated: $output_file" >&2
}

# --------------------------------------------------------------
# Input appendices with live preview update
# --------------------------------------------------------------
input_applications_live() {
    echo >&2
    read -p "How many appendices to add? (0 if none): " app_count >&2
    if ! [[ "$app_count" =~ ^[0-9]+$ ]]; then
        app_count=0
    fi
    if [ "$app_count" -eq 0 ]; then
        return
    fi
    for ((i=1; i<=app_count; i++)); do
        echo >&2
        echo "--- Appendix $i ---" >&2
        read -p "Title: " title >&2
        APP_TITLES+=("$title")
        build_docx_to_file "$LIVE_FILE"  # update after title

        read -p "Number of pages (ENTER if not needed): " pages >&2
        APP_PAGES+=("$pages")
        build_docx_to_file "$LIVE_FILE"  # update after pages

        echo "Appendix text (empty line - end):" >&2
        local text=""
        local line_num=1
        while true; do
            read -p "$line_num> " line >&2
            if [ -z "$line" ]; then
                break
            fi
            text="${text}${line}\n"
            ((line_num++))
            build_docx_to_file "$LIVE_FILE"  # update after each line
        done
        APP_TEXTS+=("$text")
        build_docx_to_file "$LIVE_FILE"  # final update after appendix
    done
}

# --------------------------------------------------------------
# Input placeholders with live preview update
# --------------------------------------------------------------
input_placeholders_live() {
    local placeholders=("$@")
    # Initialize with empty values
    for ph in "${placeholders[@]}"; do
        if [ "$ph" != "{APPENDICES}" ]; then
            placeholder_values["$ph"]=" "
        fi
    done

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
        build_docx_to_file "$LIVE_FILE"
    done
}
 
# --------------------------------------------------------------
# Save final version
# --------------------------------------------------------------
save_final() {
    read -p "Save final version? (y/n): " answer >&2
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        read -p "Output file name (without extension): " final_name >&2
        [ -z "$final_name" ] && final_name="output_$(date +%Y%m%d_%H%M%S)"
        final_name="${final_name}.docx"
        final_path="$OUTPUT_DIR/$final_name"
        cp "$LIVE_FILE" "$final_path"
        echo "Final version saved: $final_path" >&2
    else
        echo "Preview file remains: $LIVE_FILE" >&2
    fi
}

# --------------------------------------------------------------
# Main block
# --------------------------------------------------------------
select_template

mapfile -t all_placeholders < <(extract_placeholders "$TEMPLATE_FILE")
for ph in "${all_placeholders[@]}"; do
    if [ "$ph" != "{APPENDICES}" ]; then
        placeholder_values["$ph"]=" "
    fi
done
build_docx_to_file "$LIVE_FILE"

mapfile -t placeholders < <(extract_placeholders "$TEMPLATE_FILE")
input_applications_live
input_placeholders_live "${placeholders[@]}"
save_final
