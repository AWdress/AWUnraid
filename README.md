# AW Unraid

原生 SwiftUI Unraid 管理 App，当前目标为 Unraid 7.1.2 + Unraid Connect 插件。工程 target 暂保留 `UnraidPilot`，设备桌面显示名称为 `AW Unraid`。

目标设备：iPhone 17 Pro / iOS 26.5.2。最低部署版本仍保持 iOS 16，以便工程兼容更多自签设备。

## 当前状态

- 已完成暗色原生首页、阵列磁盘、Docker 列表和设置页骨架。
- 默认使用 Mock 数据，便于无服务器时开发界面。
- 已实现 GraphQL HTTP、`x-api-key` 认证与 Keychain 保存。
- 已根据实际 Unraid 7.1.2 Schema 完成 Dashboard、阵列、磁盘、Docker 与 VM 解码。
- 已确认测试插件为 Unraid Connect `2026.06.18.1729` 并完成 Schema 采集；Developer Sandbox 联调后可以关闭。
- 已实现 Docker、阵列、Parity 与 VM 的核心控制 Mutation，以及容器日志、系统日志和告警读取。
- 已加入 GitHub Actions macOS 未签名 IPA 构建工作流。

## 在 macOS 生成工程

1. 安装 Xcode 15+ 与 XcodeGen。
2. 在仓库根目录执行 `xcodegen generate`。
3. 打开 `UnraidPilot.xcodeproj`。
4. 免费 Apple ID 自签时，在 Signing & Capabilities 选择 Personal Team 并更换 Bundle Identifier。

## 证书重签交付

如果使用现有证书签名，不需要把证书或密码提供给项目。开发侧生成未签名 IPA：

```bash
chmod +x scripts/build-unsigned-ipa.sh
./scripts/build-unsigned-ipa.sh
```

输出为 `build/UnraidPilot-unsigned.ipa`，之后可使用你自己的签名工具、证书和描述文件重签。App 当前不申请推送、iCloud、App Groups 等特殊 entitlement，降低重签失败概率。

## 安全提供接入资料

不要提交 API Key、root 密码或 Cookie。只需要以下脱敏资料：

- Unraid Connect 插件准确名称及版本。
- GraphQL Endpoint 路径。
- GraphQL Schema introspection JSON，Schema 本身不含凭据。
- 对常用管理动作的优先级排序。

可以在 Unraid GraphQL Sandbox 中导出 Schema，或将 GraphQL 文档页的查询类型截图发来。API Key 仅在 App 设置页输入并保存在设备 Keychain。
