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

# 1. 缓存展示函数
show_cache() {
    if command -v glow &> /dev/null; then
        glow -p "$CACHE_FILE"
    else
        less -r "$CACHE_FILE"
    fi
}

# 2. Token 估算函数 (字符数 / 4)
estimate_tokens() {
    local text="$1"
    local char_count=$(echo -n "$text" | wc -c)
    echo $((char_count / 4))
}

# 3. API 调用核心函数
call_deepseek() {
    local content_chunk="$1"
    local system_prompt="你是一个 Linux 专家。请将此 man 手册片段翻译成中文 Markdown。保留所有命令参数、技术术语（如 -rf, syscall）不翻译。只输出翻译后的 Markdown 内容，不要包含代码块包裹符（如 \`\`\`markdown）。"
    
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

    # 提取内容并处理潜在错误
    local result=$(echo "$response" | jq -r '.choices[0].message.content')
    
    if [ "$result" == "null" ]; then
        echo "API_ERROR"
    else
        echo "$result"
    fi
}

# ================= 主逻辑 =================

# 1. 检查缓存
if [ -f "$CACHE_FILE" ]; then
    show_cache
    exit 0
fi

# 2. 获取并清洗 man 内容
echo -e "\033[36m正在获取 '$CMD_NAME' 的 man 手册...\033[0m"
# 获取 man 内容，如果失败则尝试 --help
MAN_CONTENT=$(man -P cat "$CMD_NAME" 2>/dev/null | col -b)

if [ -z "$MAN_CONTENT" ]; then
    echo "尝试获取 --help 内容..."
    MAN_CONTENT=$($CMD_NAME --help 2>/dev/null)
fi

if [ -z "$MAN_CONTENT" ]; then
    echo "Error: 无法获取 '$CMD_NAME' 的帮助信息。"
    exit 1
fi

# 3. Token 检查
EST_TOKENS=$(estimate_tokens "$MAN_CONTENT")
echo "预估 Token 数: $EST_TOKENS (限制: $MAX_TOKEN_LIMIT)"

ACTION="translate" # 默认动作

# 如果设置了限制 且 超过限制
if [ "$MAX_TOKEN_LIMIT" -gt 0 ] && [ "$EST_TOKENS" -gt "$MAX_TOKEN_LIMIT" ]; then
    echo -e "\033[1;33m[警告] 文档过长！预估 Token ($EST_TOKENS) 超过设定阈值 ($MAX_TOKEN_LIMIT)。\033[0m"
    echo "请选择操作："
    
    options=("直接翻译 (可能超长失败)" "分段翻译 (较慢但稳妥)" "取消操作")
    select opt in "${options[@]}"; do
        case $opt in
            "直接翻译 (可能超长失败)")
                ACTION="translate"
                break
                ;;
            "分段翻译 (较慢但稳妥)")
                ACTION="split"
                break
                ;;
            "取消操作")
                exit 0
                ;;
            *) echo "无效选择";;
        esac
    done
fi

# 4. 执行翻译
echo -e "\033[36m正在请求 DeepSeek API ($ACTION 模式)...\033[0m"

if [ "$ACTION" == "translate" ]; then
    # === 模式 A: 直接翻译 ===
    RESULT=$(call_deepseek "$MAN_CONTENT")
    
    if [ "$RESULT" == "API_ERROR" ]; then
        echo "翻译失败。可能是 Token 超出模型单次上限。"
        exit 1
    fi
    
    echo "$RESULT" > "$CACHE_FILE"

elif [ "$ACTION" == "split" ]; then
    # === 模式 B: 分段翻译 ===
    # 创建临时分割目录
    TMP_SPLIT_DIR=$(mktemp -d)
    
    # 计算每个 chunk 的字节数限制 (Token * 4)
    # 稍微留点余量，乘以 3.5 比较保险，或者严格按 4
    BYTES_LIMIT=$((MAX_TOKEN_LIMIT * 4))
    
    # 使用 split -C 按行切割，避免切断单词
    # -C size: put at most size bytes of lines per output file
    echo "$MAN_CONTENT" | split -C "$BYTES_LIMIT" - "$TMP_SPLIT_DIR/chunk_"
    
    CHUNK_FILES=("$TMP_SPLIT_DIR"/chunk_*)
    TOTAL_CHUNKS=${#CHUNK_FILES[@]}
    
    echo "文档已分割为 $TOTAL_CHUNKS 部分，开始逐个翻译..."
    
    # 初始化缓存文件
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
            rm "$CACHE_FILE" # 删除不完整文件
            exit 1
        fi
        
        echo "$PART_RESULT" >> "$CACHE_FILE"
        echo -e "\n\n---\n\n" >> "$CACHE_FILE" # 添加分隔符
        ((CURRENT_INDEX++))
    done
    
    echo -e "\n分段翻译完成。"
    rm -rf "$TMP_SPLIT_DIR"
fi

# 5. 展示结果
show_cache