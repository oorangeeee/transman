#!/bin/bash

# ================= 基础配置 =================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.man_translator"
CACHE_DIR="$INSTALL_DIR/cache"
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_SRC="trans.sh"

echo -e "${BLUE}=== 开始安装 tman ===${NC}"

# 1. 确定 Shell 配置文件 (Source of Truth)
# ------------------------------------------------
RC_FILE="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
    RC_FILE="$HOME/.zshrc"
elif [[ "$SHELL" == *"zsh"* ]]; then
    RC_FILE="$HOME/.zshrc"
fi
echo "检测到 Shell 配置文件: $RC_FILE"

# 2. 基础安装逻辑
# ------------------------------------------------
if [ ! -f "$SCRIPT_SRC" ]; then
    echo -e "${RED}Error: 找不到 $SCRIPT_SRC${NC}"; exit 1
fi

mkdir -p "$CACHE_DIR"
cp "$SCRIPT_SRC" "$INSTALL_DIR/tman"
chmod +x "$INSTALL_DIR/tman"

# 依赖检查函数
install_package() {
    local pkg=$1
    if ! command -v "$pkg" &> /dev/null; then
        echo -e "${YELLOW}安装依赖: $pkg${NC}"
        # 简单适配常见包管理器
        if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y "$pkg"
        elif command -v yum &> /dev/null; then sudo yum install -y "$pkg"
        elif command -v brew &> /dev/null; then brew install "$pkg"
        else echo -e "${RED}请手动安装 $pkg${NC}"; exit 1; fi
    fi
}

install_package "curl"
install_package "jq"

# Glow 检查
if ! command -v glow &> /dev/null; then
    echo -n "是否安装 'glow' (推荐)? (y/n) [y]: "
    read -r INSTALL_GLOW
    INSTALL_GLOW=${INSTALL_GLOW:-y}
    if [[ "$INSTALL_GLOW" =~ ^[Yy]$ ]]; then
        if command -v go &> /dev/null; then go install github.com/charmbracelet/glow@latest
        elif command -v apt-get &> /dev/null; then sudo apt-get install glow 2>/dev/null || echo "Apt源无glow，跳过。"
        fi
    fi
fi

# 3.API Key 同步机制
# ------------------------------------------------
echo -e "${BLUE}--- 配置同步 ---${NC}"

FINAL_API_KEY=""

# A. 检查当前环境 (最高优先级)
if [ -n "$DEEPSEEK_API_KEY" ]; then
    echo "发现环境变量中已存在 API Key。"
    FINAL_API_KEY="$DEEPSEEK_API_KEY"

# B. 检查 Shell 配置文件 (防止未生效但已写入)
elif grep -q "export DEEPSEEK_API_KEY=" "$RC_FILE"; then
    echo "发现 $RC_FILE 中已存在 API Key。"
    # 提取 key 值 (处理可能的引号)
    FINAL_API_KEY=$(grep "export DEEPSEEK_API_KEY=" "$RC_FILE" | cut -d'=' -f2 | tr -d "'\"" | tail -n 1)
fi

# C. 如果都不存在 -> 询问并双写
if [ -z "$FINAL_API_KEY" ]; then
    echo -e "${YELLOW}未检测到 API Key。请输入 DeepSeek API Key:${NC}"
    read -r USER_INPUT
    
    if [ -z "$USER_INPUT" ]; then
        echo -e "${RED}Error: 必须提供 API Key 才能继续。${NC}"
        exit 1
    fi
    
    FINAL_API_KEY="$USER_INPUT"
    
    # 写入 Shell 配置文件
    echo "" >> "$RC_FILE"
    echo "# DeepSeek API Key" >> "$RC_FILE"
    echo "export DEEPSEEK_API_KEY='$FINAL_API_KEY'" >> "$RC_FILE"
    echo "已将 Key 写入 $RC_FILE"
else
    echo "将复用现有的 API Key。"
fi

# 4. 生成工具配置文件 (config.env)
# ------------------------------------------------
echo -e "\n${YELLOW}设定 Max Token 阈值 (0 代表不限制):${NC}"
read -r token_limit
token_limit=${token_limit:-0}
if ! [[ "$token_limit" =~ ^[0-9]+$ ]]; then token_limit=0; fi

# 无论 Key 来源如何，都将其同步写入 config.env
# 这样 trans.sh 运行时不需要依赖 shell 的 export，更加稳定
cat > "$CONFIG_FILE" <<EOF
export DEEPSEEK_API_KEY="$FINAL_API_KEY"
export MAX_TOKEN_LIMIT=$token_limit
EOF

echo "工具配置已同步至: $CONFIG_FILE"

# 5. 配置 Alias
# ------------------------------------------------
if ! grep -q "alias tman=" "$RC_FILE"; then
    echo "alias tman='$INSTALL_DIR/tman'" >> "$RC_FILE"
    echo "Alias 'tman' 已添加。"
fi

echo -e "${GREEN}=== 安装完成！请执行 source $RC_FILE ===${NC}"