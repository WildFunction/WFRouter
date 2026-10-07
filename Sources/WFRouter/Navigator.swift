import UIKit
import WildFunctionKit

/// Route hub: modules register page builders by route type and navigation dispatches on that type.
///
/// In-app navigation uses strongly typed ``Route`` values; external URLs are first parsed into a route.
/// If the destination is ``RouteConfigurable``, `configure(with:info:)` runs before it is shown.
@MainActor
public final class Navigator {
    /// Shared instance.
    public static let shared = Navigator()

    private typealias Builder = @MainActor (any Route) -> UIViewController?
    private typealias DeeplinkParser = @MainActor (URL) -> (any Route)?

    private var builders: [ObjectIdentifier: Builder] = [:]
    private var deeplinkParsers: [String: DeeplinkParser] = [:]

    /// Deeplink schemes to accept (case-insensitive). Empty means any. Set this before shipping.
    public var allowedDeeplinkSchemes: Set<String> = []

    /// Overrides where the root view controller comes from when no `source` is given.
    /// Defaults to the key window's root of the foreground scene.
    public var rootViewControllerProvider: (@MainActor () -> UIViewController?)?

    /// Creates a separate navigator. Mostly useful in tests; apps use ``shared``.
    public init() {}

    // MARK: - Registration

    /// Installs modules by calling ``RouteModule/register(in:)`` on each.
    public func install(_ modules: [any RouteModule.Type]) {
        modules.forEach { $0.register(in: self) }
    }

    /// Registers the builder for a route type. The latest registration wins.
    ///
    /// - Parameters:
    ///   - type: The route type.
    ///   - builder: Creates the page, or returns `nil` when the route cannot be opened.
    public func register<R: Route>(_ type: R.Type, builder: @escaping @MainActor (R) -> UIViewController?) {
        let key = ObjectIdentifier(type)
        if builders[key] != nil {
            AppLog.warning("Route \(type) registered more than once, the latest wins", category: .router)
        }
        builders[key] = { route in
            guard let typed = route as? R else { return nil }
            return builder(typed)
        }
    }

    /// Registers a deeplink parser keyed by URL host (case-insensitive).
    ///
    /// The parser validates parameters and returns `nil` when they are invalid.
    public func registerDeeplink(host: String, parser: @escaping @MainActor (URL) -> (any Route)?) {
        let key = host.lowercased()
        if deeplinkParsers[key] != nil {
            AppLog.warning("Deeplink host \(key) registered more than once, the latest wins", category: .router)
        }
        deeplinkParsers[key] = parser
    }

    // MARK: - Resolving

    /// Parses an external URL into a route. Returns `nil` for a disallowed scheme or unknown host.
    public func route(from url: URL) -> (any Route)? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else {
            AppLog.warning("Deeplink rejected, missing scheme or host", category: .router)
            return nil
        }
        let allowed = Set(allowedDeeplinkSchemes.map { $0.lowercased() })
        guard allowed.isEmpty || allowed.contains(scheme) else {
            AppLog.warning("Deeplink rejected, scheme \(scheme) is not allowed", category: .router)
            return nil
        }
        guard let parser = deeplinkParsers[host] else {
            AppLog.warning("Deeplink rejected, no parser registered for host \(host)", category: .router)
            return nil
        }
        return parser(url)
    }

    /// Builds and configures the page for a route without presenting it.
    public func makeViewController(for route: any Route, info: RouteInfo) -> UIViewController? {
        guard let builder = builders[ObjectIdentifier(type(of: route))] else {
            AppLog.error("No builder registered for route \(type(of: route))", category: .router)
            return nil
        }
        guard let viewController = builder(route) else { return nil }

        if let configurable = viewController as? any RouteConfigurable,
           !configurable.applyRoute(route, info: info) {
            AppLog.warning(
                "\(type(of: viewController)) does not accept route \(type(of: route)), configure skipped",
                category: .router
            )
        }
        return viewController
    }

    // MARK: - Navigation

    /// Opens a route.
    ///
    /// Repeated taps are absorbed here: while the source's navigation stack is mid-transition, or the
    /// source already presents a page, the call is ignored and returns `false` without building the page.
    ///
    /// - Parameters:
    ///   - route: The destination route.
    ///   - style: How to show it. Defaults to push.
    ///   - source: The originating page. Defaults to the top-most page.
    /// - Returns: Whether navigation started.
    @discardableResult
    public func open(
        _ route: any Route,
        style: RouteStyle = .push(),
        from source: UIViewController? = nil
    ) -> Bool {
        open(route, style: style, from: source, url: nil)
    }

    /// Opens an external URL (deeplink).
    ///
    /// - Returns: `true` when the URL resolved to a route and navigation started.
    @discardableResult
    public func open(
        url: URL,
        style: RouteStyle = .push(),
        from source: UIViewController? = nil
    ) -> Bool {
        guard let route = route(from: url) else { return false }
        return open(route, style: style, from: source, url: url)
    }

    /// Pops a page. Defaults to the top-most page.
    public func pop(from source: UIViewController? = nil, animated: Bool = true) {
        let origin = source ?? topViewController()
        origin?.navigationController?.popViewController(animated: animated)
    }

    /// Dismisses a modal page. Defaults to the top-most page.
    public func dismiss(from source: UIViewController? = nil, animated: Bool = true) {
        let origin = source ?? topViewController()
        origin?.dismiss(animated: animated)
    }

    // MARK: - Top view controller

    /// The top-most visible page.
    public func topViewController() -> UIViewController? {
        let root = if let rootViewControllerProvider {
            rootViewControllerProvider()
        } else {
            Self.keyWindowRootViewController()
        }
        return Self.topViewController(from: root)
    }

    /// Walks down from `root` through presented, navigation and tab containers.
    public static func topViewController(from root: UIViewController?) -> UIViewController? {
        guard let root else { return nil }
        if let presented = root.presentedViewController, !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.topViewController) ?? navigation
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController) ?? tab
        }
        return root
    }

    // MARK: - Private

    private func open(_ route: any Route, style: RouteStyle, from source: UIViewController?, url: URL?) -> Bool {
        guard let origin = source ?? topViewController() else {
            AppLog.error("Cannot open \(type(of: route)), no source view controller found", category: .router)
            return false
        }
        if let reason = Self.busyReason(origin, style: style) {
            AppLog.info("Ignored \(type(of: route)), \(reason)", category: .router)
            return false
        }
        let info = RouteInfo(source: origin, style: style, url: url)
        guard let destination = makeViewController(for: route, info: info) else { return false }

        switch style {
        case let .push(animated):
            if let navigation = origin as? UINavigationController ?? origin.navigationController {
                navigation.pushViewController(destination, animated: animated)
            } else {
                AppLog.info("Source is not in a navigation stack, presenting instead of pushing", category: .router)
                present(destination, from: origin, style: .automatic, wrapInNavigation: true, animated: animated)
            }
        case let .present(presentationStyle, wrapInNavigation, animated):
            present(
                destination,
                from: origin,
                style: presentationStyle,
                wrapInNavigation: wrapInNavigation,
                animated: animated
            )
        }
        return true
    }

    /// Why `origin` cannot start another navigation right now, or `nil` when it can.
    ///
    /// A double tap on a button or row fires two opens within one transition. Without this, a push stacks
    /// the same page twice; a present is dropped by UIKit with only a console warning.
    private static func busyReason(_ origin: UIViewController, style: RouteStyle) -> String? {
        if origin.presentedViewController != nil {
            return "source is already presenting a page"
        }
        if origin.transitionCoordinator != nil {
            return "source is mid-transition"
        }
        if case .push = style,
           let navigation = origin as? UINavigationController ?? origin.navigationController,
           navigation.transitionCoordinator != nil {
            return "navigation stack is mid-transition"
        }
        return nil
    }

    private func present(
        _ destination: UIViewController,
        from origin: UIViewController,
        style: UIModalPresentationStyle,
        wrapInNavigation: Bool,
        animated: Bool
    ) {
        let needsWrapping = wrapInNavigation && !(destination is UINavigationController)
        let presented = needsWrapping ? UINavigationController(rootViewController: destination) : destination
        presented.modalPresentationStyle = style
        origin.present(presented, animated: animated)
    }

    private static func keyWindowRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow?.rootViewController
    }
}

extension UIViewController {
    /// Opens a route from this page via `Navigator.shared`.
    @discardableResult
    public func wf_open(_ route: any Route, style: RouteStyle = .push()) -> Bool {
        Navigator.shared.open(route, style: style, from: self)
    }
}
