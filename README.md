# ClosetAI

> 🤖 本项目 100% 由 AI 构建，欢迎各位开发者自由使用。如果在使用过程中遇到任何问题，建议直接去问问 AI —— 毕竟它比我更了解这段代码。

> An AI-powered wardrobe management iOS app built with SwiftUI. Automatically tag your clothing with AI, create outfit collages, and try on outfits virtually — all on-device with your own API key.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-26.0+-blue)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-26_beta-blue)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 📽️ Demo

<video src="https://github.com/user-attachments/assets/73f9095e-bbaf-4dd1-8f54-b1baae1ff98c" controls width="320"></video>

---

## ✨ Features

### 衣橱管理（Wardrobe）
- 📸 **AI 自动打标** — 拍照 / 相册上传，通义千问 Qwen-VL 自动识别大类、颜色、风格、季节、场合
- 🖼️ **背景消除 + 平铺图** — 自动去背景，生成标准化 flat-lay 展示图
- 🗂️ **分类浏览** — 上装 / 外套 / 连衣裙 / 下装 / 鞋子 / 包包 / 配饰各自独立横栏
- 🔍 **全文检索** — 跨颜色、风格、类别、备注的实时搜索
- ✏️ **标签编辑** — Chip 单选大类，多选季节 / 场合，自由编辑小类 / 图案

### 穿搭创建（Outfit）
- 🎨 **AI 穿搭推荐** — 根据场合、季节、数量偏好，AI 从衣橱中智能组搭并生成推荐语
- 🖼️ **AI 平铺图生成** — 通义 Wan2.6 生成高质量 flat-lay 穿搭大图
- 👗 **虚拟试穿** — 选择模特图 + 穿搭，AI 合成上身效果，支持左右滑动对比
- ✋ **手动组搭** — 手动选取最多 4 件单品，即时组建穿搭方案

### 数据洞察（Settings）
- 📊 **颜色分布** — 可视化衣橱色系占比，区分灰 / 米 / 卡其等细分色名
- 🕐 **久未穿着** — 统计 90 天内未出现在穿搭中的单品
- 🔑 **API Key 管理** — 本地 Keychain 安全存储，不上传任何服务器

---

## 🏗️ Architecture

```
ClosetAI/
├── App/                  # Entry point, ContentView, TabView
├── Models/               # ClothingTags, ClothingItemModel, OutfitModel
├── Persistence/          # CoreData stack, PersistenceController, entity extensions
├── Services/
│   ├── AliyunService.swift      # DashScope API (auto-tag, collage, try-on)
│   └── ImageProcessingService.swift  # Background removal, flat-lay generation
├── ViewModels/
│   ├── WardrobeViewModel.swift  # Wardrobe CRUD, search, statistics
│   └── OutfitViewModel.swift    # Outfit creation, AI calls, save logic
├── Views/
│   ├── Components/       # ViewExtensions (Toast), TagView, AsyncImageView
│   ├── Wardrobe/         # WardrobeView, ClothingDetailView, CameraView
│   ├── Outfit/           # OutfitView, TryOnView, ManualOutfitView
│   └── Settings/         # SettingsView (stats, API key, not-worn items)
├── Utilities/            # AppColors
└── Resources/            # Assets, model_person.png (default try-on model)
```

**Pattern:** SwiftUI + MVVM + CoreData
**Dependency:** [Kingfisher](https://github.com/onevcat/Kingfisher) (remote image loading)

---

## 📱 Requirements

| Item | Requirement |
|------|-------------|
| iOS | 26.0+ (Xcode 26 beta) |
| Device | iPhone with camera |
| API | [阿里云 DashScope](https://dashscope.aliyun.com/) API Key（免费额度可用） |
| Tool | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |

> **Note:** This project targets iOS 26 and requires Xcode 26 beta. It uses `Wan2.6-image` and `Qwen-VL-Plus` models from Alibaba Cloud DashScope.

---

## 🚀 Getting Started

### 1. Clone & Generate Project

```bash
git clone https://github.com/<your-username>/ClosetAI.git
cd ClosetAI

# Install XcodeGen if needed
brew install xcodegen

# Generate the Xcode project
xcodegen generate
```

### 2. Configure Signing

Edit `project.yml` and fill in your Apple Developer Team ID:

```yaml
settings:
  base:
    PRODUCT_BUNDLE_IDENTIFIER: com.yourname.closetai  # Change as needed
    DEVELOPMENT_TEAM: "XXXXXXXXXX"                    # Your Apple Team ID
```

Then regenerate:
```bash
xcodegen generate
```

### 3. Open in Xcode

```bash
open ClosetAI.xcodeproj
```

Select your device and hit **Run** (⌘R).

### 4. Add Your DashScope API Key

On first launch, go to **设置 (Settings)** tab → enter your DashScope API Key.
The key is stored securely in iOS Keychain and never leaves your device.

Get a free API key at: [https://dashscope.aliyun.com/](https://dashscope.aliyun.com/)

---

## 🤖 AI Models Used

| Function | Model | API |
|----------|-------|-----|
| 服装自动打标 | `qwen-vl-plus` | DashScope OpenAI-compatible endpoint |
| AI 穿搭平铺图 | `wan2.6-image` | DashScope multimodal generation |
| 虚拟试穿 | `wan2.6-image` | DashScope multimodal generation |

All AI calls are made directly from the app to DashScope using your personal API key. No intermediate server involved.

---

## 🔒 Privacy & Security

- **No data collected** — all clothing photos and outfit data are stored locally in CoreData / app Documents directory
- **API key in Keychain** — stored using iOS Security framework, never hardcoded or logged
- **No analytics or tracking** of any kind
- Photos are sent to DashScope API only when you trigger AI features (tagging / outfit generation / try-on)

---

## 🗺️ Roadmap

- [ ] 穿着日历 — visual calendar of past outfits
- [ ] iCloud / OSS 云同步 — cross-device wardrobe sync
- [ ] 季节智能推荐 — weather-aware outfit suggestions
- [ ] Widget — daily outfit reminder on home screen
- [ ] CoreData → CloudKit migration

---

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

**Setup for contributors:**
1. Follow the "Getting Started" steps above
2. Use `swiftc -parse <file.swift>` for quick syntax checks without a full build
3. The project uses XcodeGen — edit `project.yml` for project structure changes, then run `xcodegen generate`

---

## 📄 License

[MIT](LICENSE)

---

## 📚 Technical Documentation

See [TECH_REPORT_v2.0.md](TECH_REPORT_v2.0.md) for detailed architecture notes, CoreData schema, and build instructions.
