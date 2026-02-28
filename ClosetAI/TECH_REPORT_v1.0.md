# ClosetAI v1.0 技术报告

> 编写时间：2026-02-27
> 版本：v1.0（首次可交付版本）
> 项目路径：`/Users/limengliu/Desktop/衣橱管理/ClosetAI/`

---

## 一、项目概述

ClosetAI 是一款 AI 驱动的 iOS 智能衣橱管理应用，核心功能包括：

| 功能模块 | 说明 |
|----------|------|
| 衣橱管理 | 拍照/相册上传服装，AI 自动打标（分类/颜色/风格/季节/场合） |
| 穿搭推荐 | 按场合从衣橱中自动推荐 2-3 套搭配方案 |
| 穿搭平铺图 | AI 生成杂志级 flat lay 效果图（wan2.6-image） |
| 虚拟试穿 | 上传模特图，AI 将推荐搭配穿到模特身上（wan2.6-image） |
| 穿搭记录 | 保存已确认的搭配，记录穿着频次和日期 |
| 数据统计 | 颜色分布、久未穿戴提醒等 |

---

## 二、技术栈

| 层次 | 技术选型 |
|------|----------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI（iOS 16.0+） |
| 架构模式 | MVVM |
| 本地持久化 | Core Data（SQLite 后端） |
| 图像处理 | UIKit / CoreImage / Vision |
| AI 推理 | 阿里云 DashScope（云端 API，无本地模型） |
| 图片加载 | Kingfisher 7.x（SPM） |
| 项目管理 | XcodeGen（`project.yml` 生成 `.xcodeproj`） |
| 密钥存储 | iOS Keychain（Security framework） |

---

## 三、目录结构

```
ClosetAI/
├── project.yml                        # XcodeGen 配置
├── TECH_REPORT_v1.0.md               # 本文档
└── ClosetAI/
    ├── App/
    │   ├── ClosetAIApp.swift          # App 入口，注册 Core Data 环境
    │   └── ContentView.swift          # TabView 根视图（衣橱/穿搭/统计/设置）
    ├── Models/
    │   └── ClothingModels.swift       # 纯 Swift 数据模型 + ClothingTags（AI 打标结果）
    ├── Persistence/
    │   ├── ClosetAI.xcdatamodeld      # Core Data schema（ClothingItem / Outfit / WearLog）
    │   ├── CoreDataEntities.swift     # NSManagedObject 子类（手动维护）
    │   └── PersistenceController.swift # CRUD 封装 + StringArrayTransformer
    ├── Services/
    │   ├── AliyunService.swift        # 所有 AI API 调用（DashScope）
    │   └── ImageProcessingService.swift # 图像预处理/去背景/平铺图生成/本地存储
    ├── ViewModels/
    │   ├── WardrobeViewModel.swift    # 衣橱数据管理、搜索过滤、添加流水线
    │   └── OutfitViewModel.swift      # 搭配推荐算法、平铺图生成、虚拟试穿
    ├── Views/
    │   ├── Components/
    │   │   ├── AsyncImageView.swift   # LocalImageView（本地路径图片加载）
    │   │   └── TagView.swift          # 标签气泡组件
    │   ├── Wardrobe/
    │   │   ├── WardrobeView.swift     # 衣橱主页（网格 + 筛选 + 搜索）
    │   │   ├── CameraView.swift       # 拍照/选图入口
    │   │   └── ClothingDetailView.swift # 单件衣物详情编辑
    │   ├── Outfit/
    │   │   ├── OutfitView.swift       # 穿搭推荐主页
    │   │   ├── TryOnView.swift        # 平铺图 + 虚拟试穿（含 ComparisonSlider）
    │   │   └── ManualOutfitView.swift # 手动组合穿搭
    │   └── Settings/
    │       └── SettingsView.swift     # API Key 配置、模特图设置
    ├── Utilities/
    │   └── AppColors.swift            # 全局颜色常量
    └── Resources/
        └── Assets.xcassets            # 图标等静态资源
```

---

## 四、核心模块详解

### 4.1 AI 服务层（AliyunService）

所有 AI 调用集中在 `AliyunService.swift`，使用阿里云 DashScope，共三个能力：

#### 4.1.1 服装自动打标（qwen-vl-plus）

- **接口**：OpenAI 兼容端点 `compatible-mode/v1/chat/completions`
- **模型**：`qwen-vl-plus`（视觉语言模型）
- **输入**：JPEG base64 图片 + 结构化提示词
- **输出**：JSON（大类/小类/主色调/图案/风格/季节/场合/备注）
- **容错**：打标失败为非致命错误，用户可手动补全

#### 4.1.2 穿搭平铺图生成（wan2.6-image）

- **接口**：`POST https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation`
- **模型**：`wan2.6-image`（注意：**同步接口**，120s timeout，非异步轮询）
- **请求格式**（关键点）：
  ```json
  {
    "model": "wan2.6-image",
    "input": {
      "messages": [{
        "role": "user",
        "content": [
          {"image": "data:image/jpeg;base64,..."},  // 图片放前面
          {"image": "data:image/jpeg;base64,..."},
          {"text": "提示词放最后"}                   // 文字放最后
        ]
      }]
    },
    "parameters": {
      "size": "1024*1024",
      "n": 1,
      "watermark": false,
      "prompt_extend": false
    }
  }
  ```
- **响应路径**：`output.choices[0].message.content[*].image`（URL，需二次下载）
- **提示词策略**（经过多轮迭代稳定下来的版本）：
  - 硬规则①②③（件数约束 + 仅用上方图片 + 保持原图）
  - 视觉软要求（白背景 flat lay，5-15°旋转，轻微叠压，柔和漫射光，杂志风格）
  - **图片在 content 数组中必须排在 text 前面**（经验证可提升内容遵从度）

#### 4.1.3 虚拟试穿（wan2.6-image，同一接口）

- 第一张图传模特，后续图传服装（最多 3 件）
- 生成尺寸固定为 `"768*1280"`，与模特图预处理尺寸一致
- 提示词要求保留人物姿态、面部、发型，服装贴合身形

> ⚠️ **重要经验**：wan2.6-image 早期文档中有一个已废弃的 `image2image/image-synthesis` 异步端点，该端点已不可用。v1.0 使用的是 `multimodal-generation/generation` 同步端点，请勿混淆。

---

### 4.2 图像处理管线（ImageProcessingService）

新增衣物的完整处理流程：

```
用户拍照/选图
    ↓
preprocessImage()     — CIAutoAdjust 自动曝光/白平衡，EXIF 方向归一化
    ↓
removeBackground()    — iOS 17+: VNGenerateForegroundInstanceMaskRequest + CIBlendWithMask
                        iOS 16:  VNGenerateObjectnessBasedSaliencyImageRequest（近似，效果有限）
    ↓
generateFlatLayImage()— 白底 1024×1024，居中缩放，轻微投影
    ↓
checkQuality()        — 最小尺寸 200×200，前景像素占比 > 5%
    ↓
saveImageToDocuments()— 仅存文件名（非完整路径），防沙箱路径变化
    ↓
autoTagClothing()     — qwen-vl-plus AI 打标
    ↓
Core Data 入库
```

**路径存储策略**：`saveImageToDocuments` 只返回文件名（如 `uuid_original.jpg`），`LocalImageView.resolvePath()` 在读取时动态拼接 `Documents/` 路径，避免 App 更新后沙箱路径变化导致图片丢失。

---

### 4.3 穿搭推荐算法（OutfitViewModel）

纯本地算法，无需 AI，实时计算：

1. **场合软过滤**：优先匹配用户选择的场合；无匹配项时降级为全量
2. **组合策略**（按优先级）：
   - 连衣裙 + 鞋子
   - 上装 + 下装（+ 随机外套）+ 鞋子
   - 第二套上下装（尽量避免重复单品）
   - 兜底：任意衣物随机组合（应对未分类情况）
3. **评分函数**（0~1）：
   - 色彩搭配 40%（互补色对 + 中性色加分）
   - 风格一致性 40%（Jaccard 相似度）
   - 新鲜度 20%（距上次推荐天数，7天满分）

---

### 4.4 数据层（Core Data）

**实体说明**：

| 实体 | 主要字段 | 备注 |
|------|----------|------|
| `ClothingItem` | id, originalImagePath, flatLayImagePath, category, subCategory, colors, pattern, styles, seasons, occasions, wearCount, lastWornDate, lastRecommendedAt, isSoftDeleted | colors/styles/seasons/occasions 为 `[String]`，通过 `StringArrayTransformer`（JSON）序列化 |
| `Outfit` | id, name, itemIDs, occasion, collagePath, isFavorite | itemIDs 以逗号拼接 UUID 字符串存储 |
| `WearLog` | id, outfitID, itemIDs, wornDate, note | 穿着记录 |

**`StringArrayTransformer`**：自定义 `ValueTransformer`，将 `[String]` 用 `JSONEncoder` 序列化为 `NSData`，在 `loadPersistentStores` 之前必须调用 `register()` 注册（否则 Core Data 读取会崩溃）。

**轻量级迁移**：已开启 `NSMigratePersistentStoresAutomaticallyOption` + `NSInferMappingModelAutomaticallyOption`，schema 小改动可自动处理。

---

### 4.5 TryOnView / ComparisonSlider

虚拟试穿页关键设计决策：

**模特图裁剪时机**：用户选图后**立即**通过 `centerCrop(_:to:CGSize(768,1280))` 裁剪，而非在展示或生成时处理。原因：生成接口 `size="768*1280"`，两端同尺寸保证 ComparisonSlider 完美对齐，无需运行时再归一化。

**Tab 栏位置**：Tab 选择器放在 `ScrollView` **外部**（VStack 顶部固定），防止内容滚动时 Tab 被滚出屏幕。

**ComparisonSlider 尺寸**：使用 `.aspectRatio(768.0/1280.0, contentMode: .fit)` 自适应宽度，不硬编码高度，保证全身图（头部到脚部）完整展示。

---

## 五、构建与部署

### 5.1 开发环境

| 项目 | 版本/路径 |
|------|-----------|
| Xcode | 26.4 beta |
| xcodebuild | Xcode-beta.app 内置 |
| XcodeGen | `brew install xcodegen`，运行 `xcodegen generate` 重建 `.xcodeproj` |
| 部署目标 | iOS 16.0+ |
| Bundle ID | `com.example.closetai`（在 project.yml 中修改） |
| Team ID | 在 `project.yml` 的 `DEVELOPMENT_TEAM` 填写你的 Apple Team ID |

> ⚠️ **注意**：`/Applications/Xcode.app`（16.2）在 macOS 14.5 上有 `AssetCatalogSimulatorAgent` / CoreSimulator spawn 崩溃 bug，**必须使用 beta 版本构建**。

### 5.2 重建项目

```bash
cd /path/to/ClosetAI
xcodegen generate   # 重建 .xcodeproj（修改 project.yml 后必须执行）
```

### 5.3 编译

```bash
xcodebuild \
  -project ClosetAI.xcodeproj \
  -scheme ClosetAI \
  -configuration Debug \
  -destination 'id=<YOUR_DEVICE_UDID>' \
  -derivedDataPath /tmp/ClosetAI_build \
  build
```

### 5.4 安装到设备

```bash
# UDID 可通过 xcrun devicectl list devices 获取
xcrun devicectl device install app \
  --device <YOUR_DEVICE_UDID> \
  "/tmp/ClosetAI_build/Build/Products/Debug-iphoneos/ClosetAI.app"
```

### 5.5 语法检查（无需完整构建）

```bash
swiftc -parse ClosetAI/Services/AliyunService.swift
```

---

## 六、API Key 配置

1. 打开 App → 「设置」Tab
2. 填入 **DashScope API Key**（格式：`sk-xxxxxxxxxxxx`）
3. Key 通过 iOS **Keychain** 存储（`kSecClassGenericPassword`），不落磁盘明文

---

## 七、与初始 PRD 的差异对照

### 7.1 已实现（超出或调整）

| PRD 原始需求 | v1.0 实际实现 | 说明 |
|-------------|--------------|------|
| AI 图像识别打标 | ✅ qwen-vl-plus 自动打标 | 覆盖 8 维度 |
| 本地穿搭推荐 | ✅ 本地算法（色彩+风格+新鲜度） | 无需联网 |
| 穿搭效果图 | ✅ wan2.6-image AI 直接生成 flat lay | 原 PRD 为 Core Graphics 合成，AI 效果更佳 |
| 虚拟试穿 | ✅ wan2.6-image 试穿效果 | 原 PRD 仅预留接口，实际接入 |
| 穿搭对比展示 | ✅ ComparisonSlider 拖拽对比 | 原 PRD 无此组件，v1.0 新增 |
| 背景去除 | ✅ Vision 框架（iOS 17+）| iOS 16 效果有限，见 §8 |

### 7.2 未实现（计划 v1.1+）

| PRD 需求 | 状态 | 说明 |
|----------|------|------|
| 阿里云 OSS 云端同步 | ❌ 未实现 | 数据仅本地存储，`ossKey` 字段预留但未使用 |
| 穿着日历视图 | ❌ 未实现 | WearLog 已入库，UI 未开发 |
| iCloud 备份 | ❌ 未实现 | — |
| 多用户/家庭衣橱 | ❌ 未实现 | — |
| 购物推荐 | ❌ 未实现 | — |

---

## 八、已知问题与局限

| 问题 | 影响 | 建议方案 |
|------|------|----------|
| iOS 16 背景去除质量差 | 平铺图有白色背景残留 | 集成 Core ML rembg-small 模型；或要求用户最低 iOS 17 |
| wan2.6 偶发超时（>120s） | 平铺图/试穿生成失败 | 加重试逻辑（当前已有 Core Graphics 降级兜底用于平铺图）|
| 平铺图有时衣物仍轻微变形 | 视觉效果 | wan2.6 属生成式模型，有创意自由度，提示词硬约束仍有概率失效 |
| 虚拟试穿仅传模特+服装图，无姿态控制 | 试穿效果不稳定 | v1.1 可尝试 ControlNet 风格的 LoRA 或专业试穿模型 |
| Outfit.itemIDs 以字符串拼接存储 | 查询不灵活 | v1.1 迁移为 Core Data 关系（ClothingItem ↔ Outfit 多对多） |
| 搭配推荐无法学习用户偏好 | 推荐多样性有限 | v1.1 引入用户反馈（点赞/不喜欢）调整评分权重 |

---

## 九、关键代码说明

### 9.1 wan2.6 API 调用（正确版本）

```swift
// AliyunService.swift - callWan26Image
// ✅ 正确端点：multimodal-generation/generation（同步，120s）
// ❌ 废弃端点：image2image/image-synthesis（异步轮询，已下线）

var content: [[String: Any]] = []
for imageData in images.prefix(4) {
    content.append(["image": "data:image/jpeg;base64,\(imageData.base64EncodedString())"])
}
content.append(["text": prompt])   // 图片必须放在 text 前面
// 响应路径：output.choices[0].message.content[*].image → URL → 二次下载
```

### 9.2 centerCrop（模特图裁剪）

```swift
// TryOnView.swift - 选图/加载时立即裁剪，与生成尺寸保持一致
private func centerCrop(_ image: UIImage, to targetSize: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    return renderer.image { _ in
        let scale = max(targetSize.width/image.size.width, targetSize.height/image.size.height)
        let drawRect = CGRect(
            x: (targetSize.width - image.size.width*scale)/2,
            y: (targetSize.height - image.size.height*scale)/2,
            width: image.size.width*scale, height: image.size.height*scale)
        image.draw(in: drawRect)
    }
}
```

### 9.3 Swift 字符串注意事项

在 Swift 字符串字面量中，**不能使用中文弯引号 `""` `''`**（会导致 parse error），使用 `「」` 或英文引号 `""` 代替。

---

## 十、后续开发建议（v1.1 优先级）

1. **【高】阿里云 OSS 云同步**：`ossKey` 字段已预留，实现上传/下载逻辑即可
2. **【高】iOS 16 背景去除**：集成 `rembg-small` Core ML 模型，或升高最低系统要求到 17.0
3. **【中】穿着日历**：WearLog 数据已完备，新增 Calendar 视图展示
4. **【中】Core Data 关系迁移**：将 `Outfit.itemIDs` 从逗号字符串改为正式多对多关系
5. **【中】试穿质量提升**：探索专用虚拟试穿模型（如 IDM-VTON API 或阿里系的试衣 API）
6. **【低】用户偏好学习**：搭配推荐加入显式反馈机制

---

*本报告覆盖 v1.0 交付状态，如需具体实现细节请参阅对应源文件。*
