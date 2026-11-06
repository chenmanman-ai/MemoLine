# MemoLine

**留住小事，腾出心思。**

MemoLine 是一款轻量、原生的 macOS 桌面便签应用。便签像照片一样，用夹子挂在屏幕顶部的绳子上，适合记录临时想法、to-do和容易忘记的小事。
将鼠标移动到屏幕顶部的菜单栏区域，绳子和便签会自动滑下来；使用完后，把鼠标移动到便签下方的空白区域，绳子和便签就会自动收起。

无需账号、无需联网，也不会上传你的便签。

## 30 秒使用演示

[![观看 MemoLine 30 秒使用演示](Documentation/memoline-demo-cover.png)](https://github.com/user-attachments/assets/0e38bbce-d4c8-4288-82d9-b235851cf0bc)

点击上方封面观看演示视频。

## 下载 MemoLine

[![下载 MemoLine 1.10](https://img.shields.io/badge/下载_MemoLine_1.10-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/chenmanman-ai/MemoLine/releases/download/v1.10/MemoLine-1.10-macOS-arm64.zip)

点击上方蓝色 **下载 MemoLine 1.10** 按钮，即可直接下载安装包。

当前版本需要：

- macOS 14 或更高版本
- Apple Silicon Mac（M1、M2、M3、M4 等）

### 三步完成安装

1. 点击蓝色下载按钮，下载 ZIP 文件。
2. 双击 ZIP 文件解压。
3. 将 `MemoLine.app` 拖入“应用程序”文件夹，然后打开。

首次启动后，MemoLine 会出现在屏幕右上角的菜单栏，并自动展开便签绳。

<details>
<summary><strong>让 Agent 帮你下载安装（可选）</strong></summary>

把下面这段话复制给支持文件下载的 Agent：

```text
请从以下 GitHub 仓库的 Releases 下载 MemoLine：

https://github.com/chenmanman-ai/MemoLine

请选择 MemoLine-1.10-macOS-arm64.zip，解压后将 MemoLine.app 安装到“应用程序”文件夹。首次运行前先告诉我，不要绕过 macOS 安全检查。
```

当前版本适用于 Apple Silicon Mac（M1、M2、M3、M4 等）。

</details>

<details>
<summary><strong>如果 macOS 提示无法验证开发者</strong></summary>

当前公开版本尚未经过 Apple 公证。如果 macOS 阻止打开，请进入：

**系统设置 → 隐私与安全性 → 仍要打开**

请只安装从本仓库 Release 页面下载的 MemoLine。

</details>

## 你可以用它做什么

- 在屏幕顶部快速记录短便签
- 在一张便签中添加多项待办
- 使用 P1–P5 标记事情的重要程度
- 设置单次提醒和稍后提醒
- 置顶重要便签
- 拖动便签调整顺序
- 切换大、中、小三种便签尺寸
- 在多个显示器之间使用便签绳
- 完成待办后，让便签自然掉落并消失
- 隐藏便签绳，需要时再展开

## 快速上手

### 展开和收起便签绳

MemoLine 默认使用自动收起模式：

- 鼠标移动到屏幕顶部的菜单栏区域：绳子和便签自动滑下。
- 鼠标移动到便签下方的空白区域：绳子和便签自动隐藏。
- 希望一直显示：点击菜单栏中的 MemoLine 图标，选择 **常驻显示**。

### 新建便签

点击菜单栏中的 MemoLine 图标，然后选择 **新建便签**；也可以点击绳子右侧的 **新建便签**。

快捷键：`Control + Option + N`

### 编辑便签

点击便签底部的编辑图标，或双击便签内容，即可直接在卡片上修改。输入会自动保存。

### 设置优先级

点击便签左上角的 P 标签，在 P1–P5 之间选择：

- **P1**：紧急
- **P2**：高
- **P3**：中
- **P4**：低
- **P5**：稍后

### 设置提醒

点击便签底部的橙色闹钟，可以选择今天稍后、明天或指定日期和时间。

第一次设置提醒时，macOS 才会询问是否允许通知。

### 完成或删除

- 勾选待办项；完成最后一项后，便签会掉落消失。
- 点击便签底部的垃圾桶可以删除整张便签。
- 误删后可以使用绳子左侧或菜单栏中的 **撤销删除**。

### 调整便签大小

点击菜单栏中的 MemoLine 图标，选择 **大小 → 大 / 中 / 小**。小尺寸可以在同一块屏幕上容纳更多便签。

## 隐私

MemoLine 完全在你的 Mac 上运行：

- 不需要注册账号
- 不使用云同步
- 不使用分析或广告 SDK
- 不监听截图、录屏或剪贴板
- 不需要屏幕录制或辅助功能权限

便签数据保存在：

```text
~/Library/Application Support/MemoLine/
```

详细信息见 [隐私说明](PRIVACY.md)。

## 当前版本说明

- 当前安装包仅支持 Apple Silicon Mac。
- 当前公开版本尚未使用 Developer ID 签名和 Apple 公证，因此首次打开可能出现安全提示。
- 提醒通知需要用户授权；即使拒绝通知权限，应用运行期间仍可提醒。

## 开发者资料

如果你希望查看源码、参与开发或自行构建：

- [参与开发](CONTRIBUTING.md)
- [实现与架构](Documentation/IMPLEMENTATION.md)
- [构建、测试与验收](Documentation/VALIDATION.md)
- [1.10 发布说明](Documentation/RELEASE_NOTES_1.10.md)
- [安全政策](SECURITY.md)

## 开源与署名

MemoLine 基于 [Tendedero](https://github.com/alejandrobujan/tendedero) 的 MIT 开源代码改造。原作者为 Alejandro Buján。

MemoLine 是独立衍生项目，不是 Tendedero 官方版本，也未获得原作者背书。MemoLine 使用全新的名称、图标和产品设计。

- [原项目 MIT License 与版权声明](LICENSE)
- [MemoLine 新增代码许可证](LICENSE-MEMOLINE)
- [第三方来源与署名](THIRD_PARTY_NOTICES.md)

---

如果 MemoLine 对你有帮助，欢迎为项目点一个 Star。
