# transman (Translator for Man Pages)

[![Chinese](https://img.shields.io/badge/Language-中文-blue.svg)](README_zh-CN.md)

**transman** is an AI-powered Linux Man Page translator based on Large Language Models (powered by DeepSeek). It translates complex and obscure English Man Pages into clear, readable Chinese in real-time, displaying them in an elegant Markdown format.

## Features

- **Smart Translation**: Utilizes DeepSeek V3 to translate technical Man Pages into easy-to-understand Chinese.
- **Local Caching**: Translated commands are cached locally (`~/.man_translator/cache`), making subsequent queries instant.
- **Token Management**: Auto-detects long documents (like `gcc` or `bash`) and offers **Split Translation** to avoid API token limits.
- **Beautiful Formatting**: Supports Markdown rendering (best experience with `glow`).
- **Non-Intrusive**: Works as a standalone tool without modifying your system's native `man` command.

## Quick Start

### Installation

Clone the repository and run the installation script:

```bash
git clone [https://github.com/your_username/transman.git](https://github.com/your_username/transman.git)
cd transman
./install.sh
```

## Usage

Basic Translation Simply use tman followed by the command name:

``` Bash
tman ls
```

Output simulation:

``` Plaintext
Fetching man page for 'ls'...
Translating with DeepSeek AI...
(Opens a clean, Chinese Markdown view of the manual)
```

2. Handling Long Documents (Token Limit) If a command's manual is too long (e.g., gcc), tman will warn you and offer options:

``` Bash
tman gcc
```

Output simulation:

``` Plaintext
Estimated Tokens: 15000 (Limit: 4000)
[Warning] Document too long!
1) Translate anyway (May fail)
2) Split translation (Slower but reliable)
3) Cancel
# Select 2 to automatically split, translate, and merge the results.
``` 

## Configuration
The configuration file is located at ~/.man_translator/config.env.

- DEEPSEEK_API_KEY: Your API key.
- MAX_TOKEN_LIMIT: Threshold for triggering the split translation warning (0 to disable).

## License

MIT