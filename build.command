#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p LocalTranslate.app/Contents/MacOS .build-cache
cp Resources/Info.plist LocalTranslate.app/Contents/Info.plist
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -O -module-cache-path .build-cache Sources/main.swift -o LocalTranslate.app/Contents/MacOS/LocalTranslate -framework Cocoa -framework NaturalLanguage
codesign --force --sign - LocalTranslate.app
print '编译完成：LocalTranslate.app'
