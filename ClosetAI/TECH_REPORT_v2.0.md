# ClosetAI v2.0 技术报告

> 编写时间：2026-02-28
> 版本：v2.0（功能完善版）
> 基于版本：v1.0 → v2.0 增量迭代
> 项目路径：`/Users/limengliu/Desktop/衣橱管理/ClosetAI/`

---

## 一、v2.0 概述

v2.0 在 v1.0 功能链路基本完整的基础上，重点完善了**持久化**、**用户体验边界**和**交互细节**，没有引入新的 AI 能力或数据模型大改。

| 方向 | 主要改动 |
|------|----------|
| 持久化补全 | 试穿结果随穿搭自动保存/加载，保存穿搭时平铺图+上身图一并写入 |
| 体验边界 | API Key 拦截、上传件数限制、空状态优化、"上次穿着"逻辑重构 |
| 交互打磨 | Toast 错误提示、滚动收起键盘、选中角标布局、颜色分布识别 |
| Bug 修复 | ComparisonSlider 裁切、"已达上限"挤压按钮、新建穿搭时上身图丢失 |

---

## 二、技术栈

与 v1.0 相同，新增说明如下：

| 层次 | 技术选型 |
|------|----------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI（iOS 26.0+，使用 Xcode 26 beta） |
| 架构模式 | MVVM |
| 本地持久化 | Core Data（SQLite 后端），已开启轻量级自动迁移 |
| 图像处理 | UIKit / CoreImage / Vision |
| AI 推理 | 阿里云 DashScope（云端 API） |
| 图片加载 | Kingfisher 7.x（SPM） |
| 项目管理 | XcodeGen（`project.yml`） |
| 密钥存储 | iOS Keychain |

> ⚠️ v2.0 部署目标升级为 **iOS 26.0**（随 Xcode 26 beta），如需兼容旧系统需回退 `project.yml` 中的 `deploymentTarget` 并重新评估 API 可用性。

---

## 三、目录结构（v2.0 变更部分）

```
ClosetAI/
├── project.yml
├── TECH_REPORT_v1.0.md
├── TECH_REPORT_v2.0.md               # 本文档
└── ClosetAI/
    ├── App/
    │   └── ClosetAIApp.swift          # v2.0 新增：首次启动安装默认模特图
    ├── Persistence/
    │   ├── ClosetAI.xcdatamodeld      # v2.0 新增：Outfit.tryOnResultPath 字段
    │   ├── CoreDataEntities.swift     # v2.0 新增：@NSManaged var tryOnResultPath
    │   └── PersistenceController.swift # v2.0 改动：createOutfit 返回 Outfit 实体
    ├── ViewModels/
    │   ├── WardrobeViewModel.swift    # v2.0 改动：lastOutfitDate / notWornRecently 重构
    │   └── OutfitViewModel.swift      # v2.0 改动：saveTryOnResult / saveOutfit 带 tryOnResult
    ├── Views/
    │   ├── Components/
    │   │   ├── AsyncImageView.swift
    │   │   ├── TagView.swift
    │   │   └── ViewExtensions.swift   # v2.0 新增：ErrorToastModifier / dismissKeyboard
    │   ├── Wardrobe/
    │   │   ├── WardrobeView.swift     # v2.0 改动：errorToast / 搜索键盘收起 / 空状态
    │   │   ├── CameraView.swift       # v2.0 改动：PhotoPickerView selectionLimit=1
    │   │   └── ClothingDetailView.swift # v2.0 改动：lastOutfitDate / 滚动收键盘
    │   ├── Outfit/
    │   │   ├── OutfitView.swift       # v2.0 改动：试穿结果展示 / 空状态 / 滚动收键盘
    │   │   ├── TryOnView.swift        # v2.0 改动：试穿结果持久化 / letterbox / errorToast
    │   │   └── ManualOutfitView.swift # v2.0 改动：4件上限 / 按钮布局 / API Key 拦截
    │   └── Settings/
    │       └── SettingsView.swift     # v2.0 改动：颜色分布增强 / lastOutfitDate / 键盘
    └── Resources/
        ├── Assets.xcassets
        └── model_person.png           # v2.0 新增：内置默认模特图
```

---

## 四、v2.0 核心改动详解

### 4.1 试穿结果持久化

**背景**：v1.0 每次进入穿搭详情都需要重新生成试穿图，成本高（约 8~10 秒 + API 调用费用）。

**方案**：

```
Outfit（CoreData）
  ├── collagePath: String?      (v1.0 已有)
  └── tryOnResultPath: String?  (v2.0 新增)
```

**流程**（新建穿搭场景，savedOutfit == nil）：

```
用户在 TryOnView 生成试穿图
    ↓
点击「保存穿搭」→ SaveOutfitSheet
    ↓
TryOnView.saveOutfit()
  ├─ 保存平铺图文件，得到 collagePath
  └─ 调用 outfitVM.saveOutfit(..., tryOnResult: outfitVM.tryOnResultImage)
         ├─ PersistenceController.createOutfit() → 返回新建 Outfit
         └─ 若 tryOnResult != nil：保存文件，写入 outfit.tryOnResultPath
```

**流程**（从已有穿搭重新试穿，savedOutfit != nil）：

```
outfitVM.tryOnResultImage onChange
    ↓
若非从磁盘加载（tryOnResultLoadedFromDisk == false）
    └─ outfitVM.saveTryOnResult(result, for: savedOutfit)
           → 删旧文件，保存新文件，更新 tryOnResultPath
```

**关键细节**：
- `tryOnResultLoadedFromDisk` flag 区分「磁盘加载」和「新生成」，防止 `onAppear` 加载触发重复写入
- `PersistenceController.createOutfit` 加 `@discardableResult` 并返回 `Outfit`，供上层直接写入 `tryOnResultPath`

---

### 4.2 默认模特图预置

**文件**：`ClosetAI/Resources/model_person.png`（项目内置，通过 `project.yml` 纳入构建资源）

**安装逻辑**（`ClosetAIApp.init()`）：

```swift
private func installDefaultModelPhotoIfNeeded() {
    let key = "closetai.modelPhotoFilename"
    // 仅在 UserDefaults 中无记录时（首次启动）执行
    guard UserDefaults.standard.string(forKey: key) == nil,
          let defaultImage = UIImage(named: "model_person") else { return }
    _ = ImageProcessingService.shared.saveImageToDocuments(defaultImage, filename: "model_photo.jpg")
    UserDefaults.standard.set("model_photo.jpg", forKey: key)
}
```

已有用户（UserDefaults 有记录）不受影响。

---

### 4.3 ComparisonSlider 展示修复

**问题**：对比滑块使用 `.fill` 裁切模式，早期在外层加 `maxHeight` 后 GeometryReader 拿到非 3:5 帧，导致头部/脚部被裁切。

**正确方案（ZStack letterboxing）**：

```swift
ZStack {
    Color(.systemGray6)                          // 灰色背景填满容器
    ComparisonSlider(beforeImage: before, afterImage: after)
        .aspectRatio(768.0 / 1280.0, contentMode: .fit)  // 3:5 子帧
}
.frame(maxWidth: .infinity, maxHeight: 340)
.clipShape(RoundedRectangle(cornerRadius: 12))
```

原理：`.fit` 在 340pt 高度容器内计算出约 204pt 宽的 3:5 子帧，GeometryReader 拿到精确比例，两侧约 70pt 灰色留白，图片完整不裁切。

---

### 4.4 Toast 错误提示（ViewExtensions.swift）

替代 v1.0 的模态 Alert，提供非阻断式错误反馈：

```swift
struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?
    // 底部红色胶囊，3.5 秒自动消失，点击手动关闭
    // .move(edge: .bottom).combined(with: .opacity) 过渡动画
}

extension View {
    func errorToast(_ message: Binding<String?>) -> some View { ... }
}
```

应用位置：
- `WardrobeView`（`.errorToast($viewModel.errorMessage)`）：替代错误 alert
- `TryOnView`（`.errorToast($outfitVM.errorMessage)`）：替代内联红色文字

同文件还保留了 `UIApplication.dismissKeyboard()` 静态方法供各处调用。

---

### 4.5 键盘收起

不加工具栏「完成」按钮，完全依赖系统手势：

| 视图 | 方案 |
|------|------|
| WardrobeView 搜索栏 | ScrollView `.scrollDismissesKeyboard(.immediately)` + TextField `.onSubmit` |
| SettingsView | List `.scrollDismissesKeyboard(.immediately)` |
| ClothingDetailView | ScrollView `.scrollDismissesKeyboard(.immediately)` |
| SaveOutfitSheet / EditOutfitSheet | Form 原生支持，无需额外处理 |

---

### 4.6 「上次穿着」逻辑重构

**v1.0 旧逻辑**：手动调用 `recordWear()` 写入 `ClothingItem.lastWornDate`，UI 中无入口，实际未使用。

**v2.0 新逻辑**：从穿搭记录反推——衣物最近一次被使用 = 包含该衣物的所有穿搭中最晚的 `createdAt`：

```swift
// WardrobeViewModel
func lastOutfitDate(for item: ClothingItem) -> Date? {
    outfits(containing: item)
        .compactMap { $0.createdAt }
        .max()
}

var notWornRecently: [ClothingItem] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    return items.filter { item in
        guard !item.isSoftDeleted else { return false }
        guard let lastWorn = lastOutfitDate(for: item) else { return true } // 从未加入穿搭
        return lastWorn < cutoff
    }
}
```

影响范围：
- `SettingsView` → `NotWornRecentlyView`：日期显示改为「上次穿着: yyyy/MM/dd」或「从未加入穿搭」
- `ClothingDetailView` 统计栏「上次穿着」字段同步更新

---

### 4.7 颜色分布识别增强（SettingsView）

`colorForName()` 从精确 `switch` 升级为**关键词优先匹配**，处理 AI 打标产生的多样化颜色名称：

| 新增色系 | 关键词示例 |
|----------|------------|
| 米白/奶白系 | 米白、奶白、象牙、珍珠白 |
| 米色/香槟系 | 米、杏、香槟、驼、大地 |
| 卡其系 | 卡其、沙色 |
| 深灰/浅灰 | 深灰、炭灰、浅灰、银灰、麻灰 |
| 酒红/深红系 | 酒红、深红、枣红、勃艮第 |
| 藏蓝/深蓝系 | 藏蓝、深蓝、海军、宝蓝 |
| 军绿/墨绿系 | 军绿、墨绿、橄榄、深绿 |
| 其他 | 薰衣草、珊瑚、焦糖、牛仔蓝、金属金/银 |

匹配逻辑：按颜色细分系优先，再回落到大色系，最终 `default` 返回 `Color(.systemGray3)`（取代原来的 `.gray`，视觉上更中性）。

---

### 4.8 用户体验边界修复

| 问题 | v1.0 状态 | v2.0 修复 |
|------|-----------|-----------|
| 创建穿搭最多 4 件（API 限制） | 无限制 | `maxSelectionCount = 4`，超出弹 alert |
| 从相册选图可选 10 张 | 默认 limit=10 | `PhotoPickerView(selectionLimit: 1)` |
| 未配 API Key 就上传/创建 | 无提示，直接失败 | WardrobeView FAB / ManualOutfitView 提前拦截 |
| 空状态图标不贴切 | 衣橱：tshirt，穿搭：rectangle.stack | 衣橱：hanger，穿搭：wand.and.stars |
| API Key 指引步骤有误 | 步骤3提到"点击头像" | 改为"左下角菜单 → 密钥管理" |
| 「已达上限」挤压完成按钮 | if 条件显示，布局跳变 | `opacity` 占位，高度固定 |
| 选中角标悬在图片外 | `ZStack + offset(x:4,y:-4)` | `.overlay(alignment: .topTrailing)` 内嵌 |
| 完成按钮中文括号 | `完成（X/4）` | `完成 (X/4)` |

---

## 五、数据层变更（Core Data）

### 5.1 Schema 变更（v1.0 → v2.0）

| 实体 | 新增字段 | 类型 | 说明 |
|------|----------|------|------|
| `Outfit` | `tryOnResultPath` | `String?`（Optional） | 虚拟试穿结果的本地文件名 |

**迁移方式**：轻量级自动迁移（已在 `loadPersistentStores` 开启 `NSMigratePersistentStoresAutomaticallyOption`），新增 Optional 字段无需手写 Mapping Model。

### 5.2 完整实体说明（v2.0）

| 实体 | 主要字段 | 备注 |
|------|----------|------|
| `ClothingItem` | id, originalImagePath, flatLayImagePath, category, subCategory, colors, pattern, styles, seasons, occasions, notes, wearCount, lastWornDate, lastRecommendedAt, isSoftDeleted, createdAt | `lastWornDate` 字段 v2.0 不再写入（保留以兼容旧数据） |
| `Outfit` | id, name, itemIDs, occasion, collagePath, tryOnResultPath, isFavorite, createdAt | `itemIDs` 逗号拼接 UUID 字符串；`tryOnResultPath` v2.0 新增 |
| `WearLog` | id, outfitID, itemIDs, wornDate, note | 已入库，暂无 UI |

---

## 六、构建与部署

与 v1.0 相同，更新 DerivedData 路径说明：

### 6.1 开发环境

| 项目 | 版本/路径 |
|------|-----------|
| Xcode | 26 beta — `~/Downloads/Xcode-beta.app` |
| DEVELOPER_DIR | `~/Downloads/Xcode-beta.app/Contents/Developer` |
| XcodeGen | `brew install xcodegen` |
| 部署目标 | iOS 26.0+ |
| Bundle ID | `com.example.closetai`（可在 project.yml 中修改） |
| Team ID | 在 `project.yml` 的 `DEVELOPMENT_TEAM` 填写你的 Apple Team ID |
| 测试设备 | iPhone 13（iOS 26 beta） |

### 6.2 标准构建流程

```bash
cd /path/to/ClosetAI

# 1. 修改源码后重建 xcodeproj（改 project.yml 时必须）
xcodegen generate

# 2. 编译
xcodebuild \
  -project ClosetAI.xcodeproj \
  -scheme ClosetAI \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  build

# 3. 部署到真机（UDID 可通过 xcrun devicectl list devices 获取）
xcrun devicectl device install app \
  --device <YOUR_DEVICE_UDID> \
  "~/Library/Developer/Xcode/DerivedData/ClosetAI-.../Build/Products/Debug-iphoneos/ClosetAI.app"
```

### 6.3 语法快速检查（无需完整构建）

```bash
swiftc -parse ClosetAI/ViewModels/WardrobeViewModel.swift
swiftc -parse ClosetAI/Views/Outfit/TryOnView.swift
# 等等，可对单文件逐一检查
```

---

## 七、与 v1.0 的完整差异对照

### 7.1 新增文件

| 文件 | 说明 |
|------|------|
| `Views/Components/ViewExtensions.swift` | ErrorToastModifier + UIApplication.dismissKeyboard() |
| `Resources/model_person.png` | 内置默认模特图（随 App 预置） |
| `TECH_REPORT_v2.0.md` | 本文档 |

### 7.2 修改文件汇总

| 文件 | 改动摘要 |
|------|----------|
| `App/ClosetAIApp.swift` | 新增 `installDefaultModelPhotoIfNeeded()` |
| `Persistence/ClosetAI.xcdatamodeld` | Outfit 实体新增 `tryOnResultPath` Optional String |
| `Persistence/CoreDataEntities.swift` | `Outfit` 类新增 `@NSManaged var tryOnResultPath: String?` |
| `Persistence/PersistenceController.swift` | `createOutfit` 改为 `@discardableResult` 并返回 `Outfit` |
| `ViewModels/WardrobeViewModel.swift` | 新增 `lastOutfitDate(for:)`，重写 `notWornRecently` |
| `ViewModels/OutfitViewModel.swift` | 新增 `saveTryOnResult()`，`saveOutfit` 加 `tryOnResult` 参数，`deleteOutfit` 清理试穿文件 |
| `Views/Wardrobe/WardrobeView.swift` | errorToast / 搜索键盘收起 / 空状态图标 / FAB API Key 拦截 |
| `Views/Wardrobe/CameraView.swift` | `PhotoPickerView` 默认 `selectionLimit = 1` |
| `Views/Wardrobe/ClothingDetailView.swift` | `lastOutfitDate` 替换 `lastWornDate`，ScrollView 滚动收键盘 |
| `Views/Outfit/OutfitView.swift` | `tryOnResultSection` 展示，试穿按钮文案，空状态图标，EditOutfitSheet 键盘 |
| `Views/Outfit/TryOnView.swift` | 试穿结果持久化逻辑，letterbox 显示，errorToast，saveOutfit 传 tryOnResult |
| `Views/Outfit/ManualOutfitView.swift` | 4件上限，按钮布局修复，API Key 拦截，英文括号 |
| `Views/Settings/SettingsView.swift` | 颜色匹配增强，`NotWornRecentlyView` 用 `lastOutfitDate`，键盘收起 |
| `project.yml` | 新增 `model_person.png` 资源，保持 iOS 26 目标 |

---

## 八、已知问题与局限（v2.0 继承）

| 问题 | 影响 | 建议方案 |
|------|------|----------|
| iOS 背景去除质量依赖系统版本 | iOS 26 以下效果有限 | 集成 Core ML rembg 模型，或提高最低系统要求 |
| wan2.6 偶发超时（>120s） | 平铺图/试穿失败 | 加重试逻辑；平铺图已有 Core Graphics 降级兜底 |
| 试穿仅传图，无姿态控制 | 效果不稳定 | 探索专用试衣模型（IDM-VTON 或阿里系 CatVTON） |
| `Outfit.itemIDs` 逗号字符串存储 | 查询不灵活 | 迁移为 Core Data 多对多关系 |
| `WearLog` 已入库但无 UI | 数据闲置 | v3.0 新增穿着日历视图 |
| 搭配推荐无用户偏好学习 | 推荐多样性有限 | 引入显式反馈（点赞/不喜欢）调整评分权重 |
| 颜色关键词匹配依赖 AI 打标一致性 | 极少数罕见色名可能落 default | 定期补充关键词映射表 |

---

## 九、关键代码说明（v2.0 新增）

### 9.1 试穿结果原子保存

```swift
// OutfitViewModel.saveOutfit（新建穿搭 + 同时写入试穿结果）
func saveOutfit(_ suggestion: OutfitSuggestion, collagePath: String,
                name: String, occasion: String, tryOnResult: UIImage? = nil) {
    let newOutfit = persistence.createOutfit(from: model)   // 返回新建 Outfit
    if let tryOnImage = tryOnResult {
        let filename = "\(newOutfit.id?.uuidString ?? UUID().uuidString)_tryon.jpg"
        if let path = imageService.saveImageToDocuments(tryOnImage, filename: filename) {
            newOutfit.tryOnResultPath = path               // 同一事务写入
        }
    }
    persistence.save()
}
```

### 9.2 letterbox ComparisonSlider

```swift
// TryOnView - 灰色底 + fit 子视图，确保 GeometryReader 拿到精确 3:5 尺寸
ZStack {
    Color(.systemGray6)
    ComparisonSlider(beforeImage: before, afterImage: after)
        .aspectRatio(768.0 / 1280.0, contentMode: .fit)
}
.frame(maxWidth: .infinity, maxHeight: 340)
.clipShape(RoundedRectangle(cornerRadius: 12))
// 原理：340pt 容器 → fit 计算出 204×340 子帧 → .fill 图片无多余裁切
```

### 9.3 「上次穿着」从穿搭推导

```swift
// WardrobeViewModel
func lastOutfitDate(for item: ClothingItem) -> Date? {
    outfits(containing: item).compactMap { $0.createdAt }.max()
}
// 使用：viewModel.lastOutfitDate(for: item) 替代 item.lastWornDate
```

### 9.4 ErrorToast（自动消失 + 防重复清除）

```swift
.onAppear {
    let captured = msg          // 捕获当前消息
    Task {
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        if message == captured { // 仅在未被手动清除时才自动关闭
            withAnimation { message = nil }
        }
    }
}
```

---

## 十、后续开发建议（v3.0 优先级）

1. **【高】穿着日历视图**：WearLog 数据已完备，按月展示穿着频次热力图
2. **【高】阿里云 OSS 云同步**：`ossKey` 字段已预留，实现上传/下载逻辑；搭配 iCloud 备份兜底
3. **【中】Core Data 关系迁移**：`Outfit.itemIDs` 从逗号字符串改为正式多对多关系，便于复杂查询
4. **【中】试穿质量提升**：探索专用虚拟试穿模型（CatVTON / IDM-VTON API）
5. **【中】用户偏好学习**：搭配推荐加入显式反馈（点赞/不喜欢），动态调整色彩/风格评分权重
6. **【低】多 AI 提供商支持**：抽象 `AIService` 协议，支持切换 OpenAI Vision / Gemini 等
7. **【低】Widget / Shortcut**：今日穿搭建议、快速添加衣物的 App Intent

---

*本报告覆盖 v2.0 交付状态。v1.0 基础架构细节（wan2.6 API 格式、图像处理管线、StringArrayTransformer 等）请参阅 `TECH_REPORT_v1.0.md`。*
