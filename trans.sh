#!/bin/bash

# ================= 环境与配置 =================
BASE_DIR="$HOME/.man_translator"
CACHE_DIR="$BASE_DIR/cache"
CONFIG_FILE="$BASE_DIR/config.env"
API_URL="https://api.deepseek.com/chat/completions"
MODEL="deepseek-chat"

# 加载配置
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: 配置文件丢失。请重新运行 install.sh"
    exit 1
fi

# 确保默认值
MAX_TOKEN_LIMIT=${MAX_TOKEN_LIMIT:-0}

# 检查依赖
for cmd in jq curl; do
    if ! command -v $cmd &> /dev/null; then echo "Error: 缺少 $cmd"; exit 1; fi
done

CMD_NAME=$1
if [ -z "$CMD_NAME" ]; then
    echo "Usage: tman <command_name>"
    exit 1
fi

CACHE_FILE="$CACHE_DIR/$CMD_NAME.md"

# ================= 辅助函数 =================

show_cache() {
    if command -v glow &> /dev/null; then
        glow -p "$CACHE_FILE"
    else
        less -r "$CACHE_FILE"
    fi
}

estimate_tokens() {
    local text="$1"
    local char_count=$(echo -n "$text" | wc -c)
    echo $((char_count / 4))
}

call_deepseek() {
    local content_chunk="$1"
    # === 修改点 1: 强化 System Prompt ===
    # 明确指示将章节名称转换为 Markdown 标题 (##)
    local system_prompt="你是一个 Linux 系统专家。请将用户提供的 Linux Man Page 翻译成中文。
要求：
1. 保持命令参数（如 -l, --all）、系统调用、技术术语为英文，不要强行翻译。
2. 格式化为清晰的 Markdown 文档。
3. 重点解释该命令的核心用途和常用参数。
4. 如果篇幅过长，请精简无关紧要的历史描述，保留核心用法。"
    
    local escaped_content=$(echo "$content_chunk" | jq -R -s '.')
    local escaped_sys=$(echo "$system_prompt" | jq -R -s '.')
    
    local payload=$(jq -n \
              --arg model "$MODEL" \
              --argjson sys "$escaped_sys" \
              --argjson content "$escaped_content" \
              '{
                model: $model,
                messages: [
                  {role: "system", content: $sys},
                  {role: "user", content: ("Translate:\n" + $content)}
                ],
                stream: false
              }')

    local response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
        -d "$payload")

    local result=$(echo "$response" | jq -r '.choices[0].message.content')
    
    if [ "$result" == "null" ]; then
        echo "API_ERROR"
    else
        echo "$result"
    fi
}

# ================= 主逻辑 =================

if [ -f "$CACHE_FILE" ]; then
    show_cache
    exit 0
fi

echo -e "\033[36m正在获取 '$CMD_NAME' 的 man 手册...\033[0m"
MAN_CONTENT=$(man -P cat "$CMD_NAME" 2>/dev/null | col -b)

if [ -z "$MAN_CONTENT" ]; then
    echo "尝试获取 --help 内容..."
    MAN_CONTENT=$($CMD_NAME --help 2>/dev/null)
fi

if [ -z "$MAN_CONTENT" ]; then
    echo "Error: 无法获取 '$CMD_NAME' 的帮助信息。"
    exit 1
fi

EST_TOKENS=$(estimate_tokens "$MAN_CONTENT")
echo "预估 Token 数: $EST_TOKENS (限制: $MAX_TOKEN_LIMIT)"

ACTION="translate"

if [ "$MAX_TOKEN_LIMIT" -gt 0 ] && [ "$EST_TOKENS" -gt "$MAX_TOKEN_LIMIT" ]; then
    echo -e "\033[1;33m[警告] 文档过长！预估 Token ($EST_TOKENS) 超过设定阈值 ($MAX_TOKEN_LIMIT)。\033[0m"
    echo "请选择操作："
    options=("直接翻译 (可能超长失败)" "分段翻译 (较慢但稳妥)" "取消操作")
    select opt in "${options[@]}"; do
        case $opt in
            "直接翻译 (可能超长失败)") ACTION="translate"; break ;;
            "分段翻译 (较慢但稳妥)") ACTION="split"; break ;;
            "取消操作") exit 0 ;;
            *) echo "无效选择";;
        esac
    done
fi

echo -e "\033[36m正在请求 DeepSeek API ($ACTION 模式)...\033[0m"

if [ "$ACTION" == "translate" ]; then
    RESULT=$(call_deepseek "$MAN_CONTENT")
    
    if [ "$RESULT" == "API_ERROR" ]; then
        echo "翻译失败。可能是 Token 超出模型单次上限。"
        exit 1
    fi
    
    # === 修改点 2: 使用 printf 写入 ===
    printf "%s\n" "$RESULT" > "$CACHE_FILE"

elif [ "$ACTION" == "split" ]; then
    TMP_SPLIT_DIR=$(mktemp -d)
    BYTES_LIMIT=$((MAX_TOKEN_LIMIT * 4))
    
    echo "$MAN_CONTENT" | split -C "$BYTES_LIMIT" - "$TMP_SPLIT_DIR/chunk_"
    
    CHUNK_FILES=("$TMP_SPLIT_DIR"/chunk_*)
    TOTAL_CHUNKS=${#CHUNK_FILES[@]}
    
    echo "文档已分割为 $TOTAL_CHUNKS 部分，开始逐个翻译..."
    
    echo "# $CMD_NAME 中文手册 (分段翻译)" > "$CACHE_FILE"
    echo "> 注意：由于文档过长，本文档由 AI 分段翻译生成，段落间可能存在上下文不连贯。" >> "$CACHE_FILE"
    echo "" >> "$CACHE_FILE"
    
    CURRENT_INDEX=1
    for chunk in "${CHUNK_FILES[@]}"; do
        echo -ne "正在翻译第 $CURRENT_INDEX / $TOTAL_CHUNKS 部分...\r"
        PART_CONTENT=$(cat "$chunk")
        PART_RESULT=$(call_deepseek "$PART_CONTENT")
        
        if [ "$PART_RESULT" == "API_ERROR" ]; then
            echo -e "\nError: 第 $CURRENT_INDEX 部分翻译失败，终止。"
            rm -rf "$TMP_SPLIT_DIR"
            rm "$CACHE_FILE"
            exit 1
        fi
        
        # === 修改点 2: 使用 printf 追加 ===
        printf "%s\n" "$PART_RESULT" >> "$CACHE_FILE"
        echo -e "\n\n---\n\n" >> "$CACHE_FILE"
        ((CURRENT_INDEX++))
    done
    
    echo -e "\n分段翻译完成。"
    rm -rf "$TMP_SPLIT_DIR"
fi

show_cache