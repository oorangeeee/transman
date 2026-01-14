# transman (Man 手册翻译助手)

[English](README.md) | **中文文档**

`transman` 是一个基于大模型（DeepSeek）的 Linux Man 手册翻译工具。它能将晦涩难懂的英文 Man Page 实时翻译成中文，并以优雅的 Markdown 格式展示。

## 特性

- **智能翻译**：使用 DeepSeek V3 将 Man 手册翻译为易读的中文，保留关键技术术语。
- **本地缓存**：翻译过的命令会自动缓存（`~/.man_translator/cache`），二次查询秒开。
- **长文档支持**：自动检测超长文档（如 `bash`, `ffmpeg`），提供**分段翻译**功能，防止 Token 溢出。
- **格式美化**：支持 Markdown 渲染（推荐配合 `glow` 使用）。
- **非侵入式**：不修改系统 Man 命令，作为独立工具存在。

## 快速开始

### 安装

克隆仓库并运行安装脚本：

```bash
git clone [https://github.com/your_username/transman.git](https://github.com/your_username/transman.git)
cd transman
./install.sh
```

## 使用示例

1. 基础翻译 使用 tman 加上你想查询的命令：

``` Bash
tman ls
```

终端输出效果：

``` Plaintext
正在获取 'ls' 的 man 手册...
正在调用 DeepSeek AI 进行翻译...
(自动打开渲染好的中文文档界面)
```

2. 处理超长文档 (Token 限制) 如果查询的手册非常长（例如 gcc），工具会触发警告并询问处理方式：

``` Bash
tman gcc
```

终端输出效果：

``` Plaintext
预估 Token 数: 15000 (限制: 4000)
[警告] 文档过长！
1) 直接翻译 (可能超长失败)
2) 分段翻译 (较慢但稳妥)
3) 取消操作
# 选择 2 将自动把文档切片翻译并合并。
```

## 配置说明

配置文件位于 ~/.man_translator/config.env。

- DEEPSEEK_API_KEY: 你的 API 密钥。
- MAX_TOKEN_LIMIT: 触发分段警告的 Token 阈值（设为 0 则不限制）。

## License

MIT