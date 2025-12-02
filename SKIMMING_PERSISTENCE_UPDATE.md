# Skimming Mode 持久化更新

## 更新概述

本次更新为 Skimming Mode（略读模式）添加了完整的数据持久化支持，确保用户生成的章节摘要即使在应用完全退出后也能保留。

## 技术实现

### 1. Core Data 模型更新

在 `Book` 实体中添加了新的属性：
- `skimmingSummaries`: String（可选）- 存储所有章节摘要的 JSON 字符串

**文件修改：**
- `Isla_Reader.xcdatamodeld/Isla_Reader.xcdatamodel/contents`
- `Models/Book.swift`

### 2. SkimmingModeService 持久化改造

**新增功能：**

#### 双层缓存机制
- **内存缓存**：快速访问，应用运行期间有效
- **持久化缓存**：基于 Core Data，应用重启后仍然有效

#### 自动持久化
```swift
func store(summary: SkimmingChapterSummary, for book: Book, chapter: SkimmingChapterMetadata)
```
- 同时保存到内存缓存和 Core Data
- 使用 JSON 格式序列化摘要字典
- 异步保存，不阻塞主线程

#### 智能加载
```swift
func cachedSummary(for book: Book, chapter: SkimmingChapterMetadata) -> SkimmingChapterSummary?
```
- 优先从内存缓存读取（最快）
- 如果内存中没有，从 Core Data 加载
- 加载后自动缓存到内存，提高后续访问速度

### 3. 视图层集成

**SkimmingModeView 更新：**
- 添加 `restoreCachedSummaries()` 方法
- 在章节加载完成后自动恢复已保存的摘要
- 确保"目录"中的绿色对勾正确显示

## 数据流程

### 首次生成摘要
1. 用户请求生成章节摘要
2. 调用 AI API 生成内容
3. 摘要同时保存到：
   - 内存缓存（快速访问）
   - Core Data 数据库（持久化）

### 应用内切换
1. 用户退出 Skimming Mode
2. 再次进入时，从内存缓存快速恢复
3. 绿色对勾立即显示

### 应用重启后
1. 进程完全退出，内存缓存清空
2. 用户重新打开应用和书籍
3. 进入 Skimming Mode 时：
   - 加载章节列表
   - 从 Core Data 恢复所有已生成的摘要
   - 填充到内存缓存
   - 绿色对勾正确显示
4. 用户可以直接查看之前生成的摘要，无需重新生成

## 存储格式

摘要以 JSON 字符串形式存储在 Book 的 `skimmingSummaries` 字段中：

```json
{
  "bookUUID-chapterOrder": {
    "chapterTitle": "章节标题",
    "readingGoal": "阅读目标",
    "structure": [...],
    "keySentences": [...],
    "keywords": [...],
    "inspectionQuestions": [...],
    "aiNarrative": "AI 叙述",
    "estimatedMinutes": 5
  },
  ...
}
```

## 测试步骤

### 基础测试
1. 打开应用，导入一本书
2. 进入 Skimming Mode
3. 浏览几个章节并生成摘要（至少3个）
4. 打开"目录"，确认已生成摘要的章节显示绿色对勾 ✅

### 应用内退出测试
5. 关闭"目录"，退出 Skimming Mode
6. 重新进入 Skimming Mode
7. 打开"目录"，确认绿色对勾仍然存在
8. 点击任意已生成的章节，确认摘要内容正确显示

### 完全退出测试（关键）
9. 完全关闭应用（从后台杀掉进程）
10. 重新打开应用
11. 找到之前的书籍，进入 Skimming Mode
12. 打开"目录"，确认：
    - ✅ 所有之前生成的章节仍显示绿色对勾
    - ✅ 未生成的章节不显示对勾
13. 点击已生成摘要的章节，确认：
    - ✅ 摘要内容立即显示（无需重新生成）
    - ✅ 内容与之前生成的一致
14. 尝试生成一个新章节的摘要
15. 再次完全退出并重新打开应用
16. 确认新生成的摘要也被正确保存

## 性能优化

- **渐进式加载**：只在需要时从磁盘加载数据
- **内存缓存**：避免重复的磁盘读取
- **异步保存**：不阻塞 UI 线程
- **增量更新**：只保存新增的摘要，不影响现有数据

## 日志输出

可以在控制台查看持久化操作的日志：
- `SkimmingModeService: 摘要已持久化 - [章节标题]`
- `SkimmingModeService: 持久化失败 - [错误信息]`

## 数据迁移

由于添加了新的 Core Data 属性，系统会自动进行轻量级数据迁移：
- 现有书籍的 `skimmingSummaries` 字段默认为 `nil`
- 不影响现有数据
- 新生成的摘要会自动保存到新字段

## 注意事项

1. **数据库兼容性**：使用了 Core Data 的自动迁移功能
2. **性能考虑**：JSON 序列化对性能的影响可以忽略不计
3. **存储空间**：每本书的摘要数据通常在几十 KB 以内
4. **CloudKit 同步**：如果启用了 CloudKit，摘要数据会自动同步到其他设备

## 未来改进建议

1. 添加摘要过期机制（如 30 天后自动清理）
2. 支持手动清除特定书籍的摘要缓存
3. 在设置中显示缓存占用的存储空间
4. 添加"刷新摘要"功能，重新生成已有的摘要
5. 支持导出/导入摘要数据

## 相关文件

- `Isla_Reader.xcdatamodeld/Isla_Reader.xcdatamodel/contents`
- `Models/Book.swift`
- `Utils/SkimmingModeService.swift`
- `Views/SkimmingModeView.swift`

