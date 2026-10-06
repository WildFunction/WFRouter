# WFRouter

[English](README.md) | 简体中文

UIKit 的强类型路由。各模块注册自己处理的路由和 deeplink；目标页面在视图加载前拿到路由参数。

## 环境要求

- iOS 18.4+，UIKit，Swift 6 语言模式，Xcode 26+
- 依赖：WildFunctionKit

## 安装

```swift
.package(url: "https://github.com/WildFunction/WFRouter.git", from: "0.2.0")
// target 依赖：.product(name: "WFRouter", package: "WFRouter")
```

## 用法

```swift
import WFRouter

// 1. 定义路由
enum DemoRoute: Route {
    case detail(id: String)
}

// 2. 各模块注册自己处理的内容
enum DemoModule: RouteModule {
    static func register(in navigator: Navigator) {
        navigator.register(DemoRoute.self) { _ in DemoDetailViewController() }
        navigator.registerDeeplink(host: "demo") { url in
            // 校验参数，不合法时返回 nil
            DemoRoute.detail(id: "…")
        }
    }
}

// 3. 启动时安装模块
Navigator.shared.install([DemoModule.self])
Navigator.shared.allowedDeeplinkSchemes = ["myapp"]

// 4. 跳转
wf_open(DemoRoute.detail(id: "42"))                       // 任意 UIViewController 内，默认 push
wf_open(DemoRoute.detail(id: "42"), style: .present())
Navigator.shared.open(url: url)                           // deeplink：myapp://demo?...
Navigator.shared.pop()
Navigator.shared.dismiss()

// 5. 可选：在视图加载前拿到路由
extension DemoDetailViewController: RouteConfigurable {
    func configure(with route: DemoRoute, info: RouteInfo) {
        guard case let .detail(id) = route else { return }
        itemID = id          // info：来源页面、打开方式、deeplink URL
    }
}
```

## 行为

1. 按路由类型找到注册的工厂，创建页面。
2. 页面遵守 `RouteConfigurable` 时调用 `configure(with:info:)`，此时视图尚未加载。
3. push 或 present。没有导航栈时 push 退化为带导航栏的 present。
4. 不传 `source` 时使用最顶层页面。
5. 路由未注册、工厂返回 `nil`、scheme 不被允许或 host 未知时，`open` 返回 `false`。

## 约定

- `configure` 里不要访问 `view`。
- deeplink 解析器必须校验参数。
- 上线前设置 `allowedDeeplinkSchemes`；为空表示不限制。
- 同一路由类型或 host 重复注册，后注册的生效。

## 测试

```bash
xcodebuild test -scheme WFRouter -destination 'platform=iOS Simulator,name=iPhone 17'
```

## 相关

[WildFunctionKit](https://github.com/WildFunction/WildFunctionKit)（基础工具） · [KirbyiOS](https://github.com/WildFunction/KirbyiOS)（页面框架）

## 开源协议

MIT，见 [LICENSE](LICENSE)。
