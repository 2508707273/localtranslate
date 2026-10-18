#!/bin/zsh
set -eu
cd "${0:A:h}"
ollama_bin=""
for candidate in /opt/homebrew/bin/ollama /usr/local/bin/ollama /Applications/Ollama.app/Contents/Resources/ollama; do
  if [[ -x "$candidate" ]]; then ollama_bin="$candidate"; break; fi
done
if [[ -z "$ollama_bin" ]]; then
  print '请先从官网安装并打开 Ollama，再重新双击此文件。'
  open 'https://ollama.com/download/mac'
  read '?按回车关闭…'
  exit 1
fi
if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null; then
  open -a Ollama || true
  for attempt in {1..20}; do
    if curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then break; fi
    sleep 1
  done
fi
print '下载 TranslateGemma 4B（约 3.3 GB）；模型保存在 Ollama 默认目录。'
"$ollama_bin" pull translategemma:4b
open LocalTranslate.app
print '准备完成。后续翻译无需联网。'
read '?按回车关闭…'
