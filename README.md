   <div align="center">
<img src="icon.png" width="15%" alt="Class Widgets 2">
<h1>Authentication</h1>

<p>A Class Widgets plugin.</p>


[![星标](https://img.shields.io/github/stars/Lyang1273/authentication_cw_pigu?style=for-the-badge&color=orange&label=%E6%98%9F%E6%A0%87)](https://github.com/Lyang1273/authentication_cw_pigu/)
[![开源许可](https://img.shields.io/badge/license-MIT-blue.svg?label=%E5%BC%80%E6%BA%90%E8%AE%B8%E5%8F%AF%E8%AF%81&style=for-the-badge)](https://github.com/Lyang1273/authentication_cw_pigu)
[![下载量](https://img.shields.io/github/downloads/Lyang1273/authentication_cw_pigu/total.svg?label=%E4%B8%8B%E8%BD%BD%E9%87%8F&color=green&style=for-the-badge)](https://github.com/Lyang1273/authentication_cw_pigu)

</div>

> [!NOTE]
>
> - 本插件仅支持 Windows（Windows Hello 依赖 WinRT）
> - 插件会以 monkey patch 方式挂钩宿主入口，属实验性质；卸载本插件即可完全还原钩子

## 介绍 / Introduction

本插件为 Class Widgets 2 提供密码与 Windows Hello 身份验证。密码以 PBKDF2-HMAC-SHA256 哈希保存，不存储明文。RinUI 设置页可添加/移除认证方式，并配置验证触发时机；认证通过全屏模态的 RinUI Dialog 完成。

本插件基于 [Class Widgets 2 SDK](https://github.com/Class-Widgets/class-widgets-sdk)。

### 功能 / Features

- **认证方式**
  - **密码**：本地 PBKDF2-HMAC-SHA256（310000 迭代 + 随机盐）哈希存储
  - **Windows Hello**：使用系统原生 PIN/生物识别弹窗（需设备已配置 Windows Hello）
  - 同时启用多种方式时，先弹出选择窗口，任一通过即可
- **认证界面**
  - 全屏半透明载体窗口 + 居中 RinUI Dialog（全屏变暗遮罩，防绕过点击）
  - 密码错误时红字提示、清空重试
  - 取消认证即视为拒绝该操作
- **验证触发时机**（可在设置页逐项开关）
  - 程序启动（取消直接退出程序）
  - 打开设置 / 打开课程编辑器
  - 插件的安装、卸载、导入、更新、启停
  - 退出或重启程序
- **设置页**：仿 Windows「登录选项」风格，方式卡片 + 触发时机开关，支持在页内添加/更改/移除密码

### 工作原理

宿主没有公开的操作拦截 API。插件以**可逆的 monkey patch** 挂钩已识别的宿主入口（如 `AppWindowManager.open/open_settings/open_editor`、`PluginManager.uninstallPlugin/setPluginEnabled`、`UpdaterBridge.startInstall`、`AppCentral.quit/restart`）：

- 每次拦截先弹认证，通过后才继续原始调用；拒绝则取消操作并保留状态
- 同类操作的 3 秒内重复触发自动放行（同一链路多次调用去重），认证弹窗存在期间的新请求一律拒绝
- Windows Hello 调用在独立线程执行，主线程保持消息泵，不会出现「未响应」
- 所有认证 UI 由 RinUI 提供，不使用原生 Qt 对话框

### 兼容性说明

- 只有插件能够识别的入口会被挂钩；若宿主版本改变了入口方法，对应触发项会失效，日志中会记录「no host hook was installed」
- Windows Hello 仅限 Windows 平台，且依赖宿主运行 Python 3.12（winrt 组件会随插件打包）

## 使用 / Usage

1. 在插件广场（网页版/客户端）中 [下载](https://plaza.cw.rinlit.cn/plugins/authentication.lyang1273) / In Plugin Plaza (Web / Class Widgets Client), [download](https://plaza.cw.rinlit.cn/plugins/authentication.lyang1273) this plugin

2. 在 Class Widgets 2 ->「设置」->「插件」中导入并启用本插件 / Import and enable this plugin in "Settings" -> "Plugins"

3. 在插件的「登录选项」设置页中：
   - 添加密码或 Windows Hello 认证方式（首次添加密码时设置并确认密码）
   - 打开需要验证的触发项（至少启用一项）

> **注意**
> - 无法拦截对**本插件自身**的启用/禁用/卸载（自身被停用后钩子已摘除）
> - 关闭「程序启动验证」后重启即可清除启动验证
> - 认证数据保存在 `配置目录/plugins/authentication.lyang1273.json`（`password_salt`/`password_hash`/`iterations`/`auth_methods`/`events`），删除该文件即可重置插件
> - Windows Hello 不可用时设置页会显示「此选项当前不可用」，不影响密码方式

## 构建 / Packaging

```
cd authentication_cw_pigu
pip install Class-Widgets-SDK
cw-plugin-pack        # 在源目录打包，生成 authentication.lyang1273.cwplugin
```

打包会依据 `pyproject.toml` 的 `project.dependencies` 自动将 winrt 组件安装进 `libs/`，宿主加载插件时会把 `libs/` 加入 `sys.path`。产物可直接通过宿主「插件 → 导入插件」安装。

## 排错 / Logging

宿主日志位于 `日志` 目录。相关关键字：

| 日志内容 | 含义 |
| --- | --- |
| `Windows Hello availability: ...` | 启动时 Hello 可用性诊断 |
| `Windows Hello call failed: ...` | WinRT 调用失败原因 |
| `Authentication hook fired: event=... method=...` | 拦截已触发 |
| `Hooked targets for event toggle state: ...` | 实际挂钩的宿主入口列表 |
| `no host hook was installed` | 触发项已启用但未找到可拦截入口（宿主兼容问题） |



## 致谢 / Acknowledgements

### 引用资源 / Credits

- [Class Widgets 2](https://github.com/rinlit-233-shiroko/class-widgets-2) — 插件宿主与 SDK 设计
- [Class Widgets 2 SDK](https://github.com/Class-Widgets/class-widgets-sdk) — 插件 API、打包工具链
- [RinUI](https://github.com/rinlit-233-shiroko/RinUI) — 全部认证 / 设置界面组件（Fluent 风格 Dialog、SettingCard 等）
- [pywinrt / winrt-runtime](https://github.com/pywinrt/pywinrt) — Windows Hello（绑定 `Windows.Security.Credentials.UI`）
- hashlib / hmac / secrets（Python 标准库）— PBKDF2-HMAC-SHA256 密码哈希

### 贡献者们 / Contributors
[![Contributors](http://contrib.nn.ci/api?repo=Lyang1273/authentication_cw_pigu)](https://github.com/Lyang1273/authentication_cw_pigu/graphs/contributors)

## 版权 / License
本项目基于 MIT 协议开源，详情请参阅 [LICENSE](https://github.com/Lyang1273/authentication_cw_pigu/blob/main/LICENSE) 文件。

The project is licensed under the MIT license. Please refer to the [LICENSE](https://github.com/Lyang1273/authentication_cw_pigu/blob/main/LICENSE) file for details.
