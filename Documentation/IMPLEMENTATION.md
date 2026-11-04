# 实施记录

## 开始编码前的源码阅读

完整阅读原 README、LICENSE、Package.swift，以及 AppDelegate.swift、LinePanel.swift、LineView.swift、PeggedView.swift、Line.swift、HotKey.swift、GrabArea.swift、FullScreen.swift、main.swift。确认 AppDelegate 启动监听、Line 恢复路径、容量淘汰及文件删除、窗口不可成为 Key 的生命周期后，才开始替换。

原结构：AppDelegate 负责菜单、监听、显隐和屏幕；Line 同时管理图片模型、文件操作和 UserDefaults 路径；LinePanel 不抢焦点；LineView/PeggedView 绘制绳子和图片。原满容量逻辑会卸下最早图片，Inbox 中的文件可能被移入废纸篓，不适用于便签。

## 保留和改造

- LinePanel：保留 `.nonactivatingPanel` 与 `canBecomeKey/Main = false`、鼠标屏幕选择；调整高度和全屏行为。
- Rope / Clothespin：提取上游绳子曲线和金属夹子；保持 MIT 署名。
- HotKey / ShortcutRecorder：保留 Carbon 思路和录制窗口；从单一静态回调改为按 ID 分发，允许新建和绳子快捷键共存。
- AppDelegate：重写协调层，保留 hover/retract、命中区域穿透和屏幕迁移思路。

## 替换与新增

- Pegged → Memo；Line → MemoStore + LineState。持久模型完全不含 URL/缩略图。
- PeggedView / LineView → HangingMemoView / MemoLineView；200 pt 卡片、五色、七行截断、温和动画。
- MemoCore 独立可测试模块；编辑器/列表/设置/新品牌图形/构建脚本/回归测试与文档。
- SwiftData 可用，但原项目无数据库结构。当前选择 Codable + 版本化文档 + 原子写入，减少迁移复杂度，便于故障注入测试。未来需要更大数据量或查询时可新增 schema 迁移。

## 从构建和交付中移除

ScreenshotWatcher、ClipboardWatcher、Inbox、Markup、Trim、QuickLook、CaptureFlight、GrabArea、旧 Line/Pegged、图片缩略图/视频框架、截图文件管理、截图设置变更和原品牌资源。旧本地化字符串也移除，第一版界面为简体中文。

## 原生全屏策略

不再链接私有 `CGSCopyManagedDisplaySpaces` / `CGSMainConnectionID`。默认使用 AppKit 非全屏辅助行为；明确开启后设置 `.fullScreenAuxiliary`。由系统 Space 管理控制窗口可见性。原生全屏、独立 Space 和多屏的组合仍需在目标系统上逐一验收；不承诺覆盖系统安全界面或独占全屏游戏。

## 明确边界

- 新建窗口是尚未提交的草稿，Command + Return 完成创建；Escape 明确取消。已有便签自动保存，退出前 flush。
- 1.6 起每张待办卡支持多个独立勾选项；编辑器每行一个任务，全部完成后沿用掉落移除及撤销行为。
- 绳子排序为置顶分组 + sortOrder；列表排序为置顶 + updatedAt。拖动不能把普通便签挤到置顶组之前。
- 全屏关闭为默认。所有外部链接仅在文档出现，程序无自动网络请求。
- 数据失败反馈不记录正文到系统日志。

## 后续可考虑（本次未实现）

手动导出/导入、本地备份历史与恢复界面、新建快捷键录制、登录启动、英文界面、键盘排序、更多辅助功能验收。账户、AI、云同步、Markdown、重复提醒、自然语言时间和日历同步不属于第一版。

默认全屏保护还使用公开的 CGWindowList 窗口几何元数据，检测前台应用是否有窗口覆盖目标显示器；不读取窗口标题或屏幕像素，不需要录屏权限。此保守策略可能把隐藏菜单栏的最大化窗口也视作全屏。关闭“允许覆盖全屏应用”时，这些窗口也会让绳子收起。


## 1.1 菜单与删除交互

按用户后续要求，待办完成的规则从保留已完成卡片改为删除并可撤销。普通文本仍可标记为完成。删除视图使用纯视觉快照，便签从夹子位置旋转下坠并淡出；Store 维护原子持久化的删除撤销栈，先落盘再播放动画。Schema 升级为 2，支持读取原 schema 1。原子写失败不消失、不留下虚假的撤销记录。

菜单栏显示紧凑的系统便签图标，以系统 NSMenu 提供新建文本/待办、绳子显隐、显示方式、大小、快捷键、撤销、关于和退出；没有复制参考截图里的截图监控功能。应用启动后只保留菜单栏、绳子和卡片，Finder reopen 改为展开绳子，不再创建独立便签管理窗口。

## 1.5 单次提醒

- `Memo` 增加提醒时间、提醒状态、最近触发时间、稍后时间和由 UUID 派生的稳定通知标识；schema 升级为 3，同时兼容 schema 1/2 缺失字段。
- `MemoStore` 是提醒状态的唯一数据来源，集中处理设置、取消、到期、确认和稍后提醒。完成、归档或删除会在同一次原子写入中清理提醒；动画不决定提醒状态。
- `ReminderController` 统一负责 UserNotifications、通知操作、每秒到期检查、重启恢复和循环声音。同一时刻可有多张 ringing 便签，但只持有一个循环 `NSSound`。
- 通知权限只在用户第一次新增或修改提醒后请求，启动时不请求。权限拒绝时保留应用运行期间的到期检查和声音，并向用户说明系统通知不可用。
- 响铃卡片临时排在绳子可见区域最前，但不改变 `isPinned` 或用户顺序。单击优先确认提醒，不触发编辑或完成；仍有其他 ringing 便签时继续播放声音。
- Reduce Motion 下取消抖动，以红色高对比边框、闹钟图标和 VoiceOver 文案提供非动画反馈。

## 1.6 暖白纸笺与多项清单

- 210 pt 暖白纸面，Canvas 静态绘制细纤维、浅褶皱和折痕高光。标签 P1–P5 使用深到浅的蓝色，独立于置顶及排序；旧颜色字段仅为兼容保留。
- 底部统一为橙色闹钟、灰色垃圾桶、灰色编辑图标。上方只保留优先级和置顶图钉。
- schema 4 新增 `MemoPriority` 和具有 UUID 的 `TodoItem`。旧数据无需预处理，旧多行待办保留为一个整体任务。
- 编辑正文时按行生成任务，精确匹配的任务保留 UUID 与勾选状态；修改任务文字后重新作为未完成项。最后一项完成通过 Store 原子删除并保留撤销记录，取消提醒。
- 卡片内垂直滚动浏览清单，横向滚动浏览绳子。列表也支持逐项勾选，全部内容仍可通过编辑器访问。
- Debug 构建支持 `--render-design-preview <输出PNG路径> [--dark]`，使用独立内存示例数据渲染原生控件，不读取真实便签或启动提醒。

## 1.7 卡片原位输入

- 绳子上的编辑入口在卡片原位置创建可成为 Key 的小型 NSPanel；沿用同一编辑控制器、NSTextView、输入法支持、自动保存和失败保护。背景使用同一 PaperSurface，原卡片暂时隐藏，夹子和绳子继续显示。
- LinePanel 自身始终不能成为 Key/Main；只有正在编辑的卡片覆盖层接收输入。编辑期间暂停绳子自动收起及跨屏迁移。
- ⌘ Return、Escape 和完成按钮提交并结束编辑。失去 Key 时保存成功才关闭；失败、空正文、超限或输入法尚在组合时保留输入区。
- 编辑已有内容时使用 Store 当前类型、提醒和清单数据的合并逻辑，已有未修改清单项的勾选状态继续保留。列表和新建保留完整窗口。
