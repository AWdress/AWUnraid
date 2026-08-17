# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Unraid 服务器的个人管理员，在 iPhone 上快速查看状态并执行日常管理操作。

## Product Purpose

AW Unraid 是面向 Unraid 7.1.2 的原生 iOS 管理 App。成功意味着用户无需打开浏览器，即可安全连接自己的服务器、判断健康状态并管理阵列、Docker、虚拟机、通知和日志。

## Positioning

以 Unraid GraphQL API 驱动原生信息架构和系统交互，而不是把 Web GUI 包装进 WebView。

## Operating Context

通过局域网 HTTP、域名 HTTPS 或用户自有网络隧道连接 Unraid Connect GraphQL Endpoint；API Key 由用户在设备上输入并存储于 Keychain。

## Capabilities and Constraints

- 目标服务器为 Unraid 7.1.2，部分能力取决于服务器是否启用 Docker、VM 和相应插件。
- App 必须在某项能力未启用时降级显示，不能让整个连接失败。
- 无 Apple Developer 账号，交付未签名 IPA，由用户使用自己的证书重签。
- 不在源码、日志或仓库中保存 API Key、证书或密码。
- 不使用内嵌网页补齐原生功能。

## Brand Commitments

产品名为 AW Unraid。界面应专业、克制、清晰，延续深色海军蓝、青色状态强调和 iOS 原生交互。

## Evidence on Hand

- 用户真机连接截图与错误状态。
- Unraid 7.1.2 实际 GraphQL Schema 和 Unraid Connect 插件接口。
- `Design/References/unraid-dashboard-dark-target.png` 作为信息密度与配色参考。

## Product Principles

- 原生能力优先，绝不以网页套壳冒充 App。
- 单项服务不可用时局部降级。
- 危险操作明确确认，凭据只留在设备 Keychain。
- 高频状态一眼可读，高级连接选项不干扰首次连接。
