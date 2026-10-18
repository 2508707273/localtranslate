# 本地译 · LocalTranslate

一个轻量的 macOS 菜单栏翻译工具。选中英语或日语文字，连按两次 **⌘C**，在鼠标附近查看中文译文。使用本机 Ollama 运行 TranslateGemma，下载模型后可离线使用。

## 功能

- 连按两次 ⌘C 打开翻译浮窗（间隔小于 0.65 秒）。
- 英语 / 日语自动识别，也可手动指定语言。
- 默认 TranslateGemma 4B，可切换到 12B。
- 手动粘贴翻译、翻译剪贴板、复制译文、Esc 关闭浮窗。
- 菜单栏暂停快捷键监听，无翻译历史或云服务配置。

## 环境

- Apple Silicon Mac，macOS 14 或更新版本。
- Xcode Command Line Tools（`xcode-select --install`）。
- [Ollama](https://ollama.com/download/mac)。
- 足够的模型磁盘空间：4B 约 3.3 GB，12B 约 8.1 GB；运行时还需额外内存。

当前构建脚本面向 arm64。M4 Max 64 GB 上已由使用者确认基础翻译可用，其他设备和系统版本尚未逐一验证。

## 从源码运行

1. 下载或克隆本仓库。
2. 在项目目录执行：

   ```sh
   zsh build.command
   ```

3. 安装并打开 Ollama，在终端运行：

   ```sh
   ollama pull translategemma:4b
   ```

   也可运行 `zsh 准备模型.command` 下载模型并启动编译后的应用。

4. 打开 `LocalTranslate.app`，点击窗口中的「快捷键权限」。
5. 在「系统设置 → 隐私与安全性 → 输入监控」中允许本地译，然后退出并重新打开应用。
6. 在其他应用选中文字，连按两次 ⌘C。

如果系统权限列表未自动出现，可使用 + 添加 `LocalTranslate.app`。建议先固定应用的存放位置，再授权。

程序使用本机临时签名，未经过 Apple 公证；重新编译后系统可能要求重新授权。无需输入监控权限也可使用窗口内的手动翻译和菜单中的「翻译剪贴板」。

## 模型

默认使用专用翻译模型 [TranslateGemma 4B](https://ollama.com/library/translategemma)。切换 12B 前运行：

```sh
ollama pull translategemma:12b
```

再从窗口下拉框选择对应模型。程序使用官方建议的英 / 日到简体中文提示格式，模型保留在内存 30 分钟，以减少后续加载等待。

## 隐私

翻译请求只发送到 `http://127.0.0.1:11434/api/chat`。应用仅在双击复制或手动触发时读取剪贴板，不保存翻译历史。软件和模型下载需要联网；翻译本身不需要联网。Ollama 是独立进程，退出本地译不会退出 Ollama。

## 已知限制

- 此版本输出纯译文，不包含词典读音、词性或多义项。
- 自动识别仅在英语和日语间选择，短词和纯汉字日语可能需要手动指定语言。
- 只读取复制后的文字，不模拟复制，不包含截图 OCR。
- Ctrl+C 连按两次也能触发，但仅适用于本身使用 Ctrl+C 复制的应用；macOS 通常使用 ⌘C。
- 安全输入模式可能阻止全局监听。
- 一次最多输入 12000 字符；长文本建议分段翻译。模型输出达到上限时会提示。
- 译文一次显示，暂未实现流式输出、开机启动或自动更新。

## 项目结构

```text
Sources/main.swift       AppKit 窗口、快捷键监听和本地翻译请求
Resources/Info.plist     应用元数据
build.command            编译并临时签名
准备模型.command          下载默认模型并启动应用
```

## 贡献

欢迎提交 Issue 和 Pull Request。请注明 macOS 版本、芯片、模型及复现步骤，示例文本请使用可公开的内容。提交修改前运行 `zsh build.command`，并按需手动验证英语、日语、快捷键和断开 Ollama 时的提示。

## 许可与致谢

本仓库代码使用 [MIT License](LICENSE)。Ollama 与 TranslateGemma 为独立依赖，不随本仓库分发；它们的软件、模型权重及相关条款由各自项目管理。

感谢 [Ollama](https://github.com/ollama/ollama) 和 [TranslateGemma](https://ollama.com/library/translategemma)。
