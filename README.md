# 书卷 · BookLeaf

苹果图书（Apple Books）风格的 iOS 阅读器，支持 **EPUB / TXT** 导入，主打 **仿真卷曲翻页**。
最低系统 **iOS 16**，Flutter 实现。

## 功能

- **书库**：两列封面网格、阅读进度、最近阅读/最近添加/书名/作者排序、长按菜单（打开 / 标记已读 / 移除）
- **阅读中**：继续阅读大卡片 + 正在阅读横滑列表
- **导入**：系统文档选择器直接导入 `.epub` / `.txt`（可多选）；也可用「文件」App / AirDrop 把书丢进书卷的 Documents 目录，下次启动自动入库；TXT 自动识别 UTF-8 / GBK，按「第X章 / 序章 / 楔子 / 番外」切章；EPUB 解析 OPF + 目录（nav.xhtml / toc.ncx），提取封面
- **阅读器**：
  - 自研排版引擎（TextPainter 逐行分页，跨章连续页码，字号/行距/字体/首行缩进/两端对齐可调）
  - **仿真卷曲翻页**：斜向折痕 + 圆柱卷曲几何，纸背不透字、折痕处文字随卷曲压缩、卷边高光与投影
  - 三种翻页：仿真 / 滑动 / 无
  - 四套主题：白 / 米黄 / 灰 / 夜
  - 目录、进度滑杆、跳转页码、阅读进度自动保存（按章 + 字符偏移恢复）
- 苹果式交互：大标题导航、Cupertino 控件、点按左/中/右区域翻页/呼出工具栏、横向拖拽翻页

## 构建

```bash
flutter pub get
flutter build ios --release --no-codesign   # 需 macOS
```

本仓库的 GitHub Actions（`.github/workflows/build-ipa.yml`）在 macOS runner 上产出未签名 IPA，
打 `v*` tag 时自动发布到 Release。

## 本地预览（Web）

```bash
flutter build web --release
python tools/serve_web.py    # http://127.0.0.1:8124
```

浏览器不支持 `RepaintBoundary.toImage`，所以 Web 预览里的仿真翻页会自动降级为滑动翻页；
想单独看卷曲效果可以构建卷曲实验室：

```bash
flutter build web -t lib/curl_lab.dart -o build/web_lab
python -m http.server 8125 -d build/web_lab
```

## 工具

- `tools/make_icon.py`：生成全套 App 图标（角标翻起的纸页）
- `tools/patch_ios.py`：把 Xcode 工程最低版本设为 iOS 16、写入中文显示名与 EPUB/TXT 文档类型
