# WFRouter

English | [简体中文](README.zh-CN.md)

Strongly typed routing for UIKit. Modules register the routes and deeplinks they handle; destinations receive their route before the view loads.

## Requirements

- iOS 18.4+, UIKit, Swift 6 language mode, Xcode 26+
- Dependency: WildFunctionKit

## Install

```swift
.package(url: "https://github.com/WildFunction/WFRouter.git", from: "0.2.1")
// target dependency: .product(name: "WFRouter", package: "WFRouter")
```

## Usage

```swift
import WFRouter

// 1. Define routes
enum DemoRoute: Route {
    case detail(id: String)
}

// 2. Each module registers what it handles
enum DemoModule: RouteModule {
    static func register(in navigator: Navigator) {
        navigator.register(DemoRoute.self) { _ in DemoDetailViewController() }
        navigator.registerDeeplink(host: "demo") { url in
            // validate parameters; return nil when invalid
            DemoRoute.detail(id: "…")
        }
    }
}

// 3. Install modules at launch
Navigator.shared.install([DemoModule.self])
Navigator.shared.allowedDeeplinkSchemes = ["myapp"]

// 4. Navigate
wf_open(DemoRoute.detail(id: "42"))                       // from any UIViewController, push by default
wf_open(DemoRoute.detail(id: "42"), style: .present())
Navigator.shared.open(url: url)                           // deeplink: myapp://demo?...
Navigator.shared.pop()
Navigator.shared.dismiss()

// 5. Optional: receive the route before the view loads
extension DemoDetailViewController: RouteConfigurable {
    func configure(with route: DemoRoute, info: RouteInfo) {
        guard case let .detail(id) = route else { return }
        itemID = id          // info: source page, style, deeplink URL
    }
}
```

## Behavior

1. The builder registered for the route type creates the page.
2. `configure(with:info:)` runs if the page is `RouteConfigurable`. The view is not loaded yet.
3. Push or present. Push without a navigation stack falls back to a present wrapped in a navigation controller.
4. Without a `source`, the top-most page is used.
5. `open` returns `false` for unregistered routes, a `nil` builder result, disallowed schemes or unknown hosts.

## Rules

- Do not touch `view` inside `configure`.
- Deeplink parsers must validate their parameters.
- Set `allowedDeeplinkSchemes` before shipping; empty means any scheme.
- Registering the same route type or host twice: the latest wins.

## Test

```bash
WFROUTER_STRICT=1 xcodebuild test -scheme WFRouter -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Related

[WildFunctionKit](https://github.com/WildFunction/WildFunctionKit) (base utilities) · [KirbyiOS](https://github.com/WildFunction/KirbyiOS) (page framework)

## License

MIT. See [LICENSE](LICENSE).
