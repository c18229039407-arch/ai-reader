# Phase 0 环境搭建手册（macOS，Apple Silicon）

目标：在你的 Mac 上准备好 Flutter 双端开发环境和本地 AI 推理环境，为 Phase 0 三条验证链路做好准备。全程照抄命令即可，每一步都附「怎么确认成功」。

预计耗时：1–2 小时（多数时间在等下载）。

---

## 1. 基础工具

### 1.1 Xcode Command Line Tools（macOS 端构建需要）

```bash
xcode-select --install
```

弹窗点「安装」。**确认成功**：`xcode-select -p` 输出一个路径（如 `/Library/Developer/CommandLineTools`）。

> 注意：构建 macOS 桌面 App 需要完整版 Xcode（App Store 免费安装，体积大，可以边下边做后面的步骤）。装好后打开一次并同意协议。

### 1.2 Homebrew（包管理器，没有的话）

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**确认成功**：`brew --version` 输出版本号。

## 2. Flutter

```bash
brew install --cask flutter
```

然后运行环境自检：

```bash
flutter doctor
```

**确认成功**：`Flutter` 一行是 ✓。macOS/Android 相关的 ✗ 按第 3、4 节逐个消掉。国内网络如遇下载慢，可先设置镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

（可写入 `~/.zshrc` 长期生效。）

## 3. macOS 桌面端支持

```bash
flutter config --enable-macos-desktop
```

**确认成功**：`flutter doctor` 中 Xcode 相关为 ✓（需要完整版 Xcode 装好并打开过一次）。

## 4. Android 端支持

1. 安装 [Android Studio](https://developer.android.com/studio)（自带 SDK）。
2. 首次启动按向导装默认组件；再到 Settings → SDK Manager → SDK Tools 勾选 **Android SDK Command-line Tools**。
3. 接受许可证：

```bash
flutter doctor --android-licenses
```

4. 手机开启开发者模式和 USB 调试，用数据线连 Mac。

**确认成功**：`flutter devices` 能同时看到 `macos` 和你的安卓手机。

## 5. Ollama（本地 AI）

```bash
brew install ollama
brew services start ollama   # 开机自启的后台服务
```

拉取 Phase 0 验证用模型（Qwen2.5 对中文最友好；先拉 7b，14b 视内存情况）：

```bash
ollama pull qwen2.5:7b
# 内存 ≥ 32GB 可以再拉：ollama pull qwen2.5:14b
```

**确认成功**：

```bash
ollama run qwen2.5:7b "用通俗语言解释什么是复利，举一个网购的例子"
```

能流式输出合理的中文回答即可。

## 6. 验证局域网链路（Phase 0 第三条链路的前置）

默认 Ollama 只监听本机。让手机（同一 Wi-Fi）能访问，需要让它监听所有网卡：

```bash
launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
brew services restart ollama
```

查你 Mac 的局域网 IP：

```bash
ipconfig getifaddr en0
```

**确认成功**：手机浏览器访问 `http://<Mac的IP>:11434`，看到 `Ollama is running`。

> 安全提示：`0.0.0.0` 会向整个局域网开放端口，只建议在家庭/可信 Wi-Fi 下开启；公共网络时改回默认（`launchctl unsetenv OLLAMA_HOST` 后重启服务）。

## 7. Syncthing（Phase 2 才用，可先装好熟悉）

```bash
brew install --cask syncthing
```

Android 端安装 Syncthing-Fork（F-Droid 或 GitHub Releases）。本阶段不必配置，Phase 2 再说。

## 8. 完成核对清单

- [ ] `flutter doctor` 全绿（或仅剩无关项警告）
- [ ] `flutter devices` 同时列出 macos 与安卓手机
- [ ] `ollama run qwen2.5:7b "..."` 正常输出中文
- [ ] 手机浏览器能打开 `http://<Mac的IP>:11434`

四项全过，环境就绪，可以开始 Phase 0 的验证代码了。
