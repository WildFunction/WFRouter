import UIKit

/// A strongly typed route. Each module defines its own enum or struct.
///
/// ```swift
/// enum DemoRoute: Route {
///     case detail(id: String)
///     case reviews(itemID: String)
/// }
/// ```
public protocol Route: Hashable, Sendable {}

/// How a page is shown.
public enum RouteStyle: Sendable, Equatable {
    /// Pushes onto the source's navigation stack. Falls back to a wrapped present when there is none.
    case push(animated: Bool = true)
    /// Presents modally, optionally wrapped in a `UINavigationController`.
    case present(
        style: UIModalPresentationStyle = .automatic,
        wrapInNavigation: Bool = true,
        animated: Bool = true
    )
}

/// Context of one navigation, handed to the destination during early configuration.
@MainActor
public struct RouteInfo {
    /// The originating page. Held weakly.
    public private(set) weak var source: UIViewController?
    /// How the page is shown.
    public let style: RouteStyle
    /// The original URL when triggered by a deeplink, otherwise `nil`.
    public let url: URL?

    /// Creates navigation info.
    public init(source: UIViewController?, style: RouteStyle, url: URL? = nil) {
        self.source = source
        self.style = style
        self.url = url
    }
}

/// Early configuration hook for a destination page.
///
/// ``Navigator`` calls ``configure(with:info:)`` after creating the page and before showing it,
/// so the view is not loaded yet. Store route parameters here.
///
/// ```swift
/// extension DemoDetailViewController: RouteConfigurable {
///     func configure(with route: DemoRoute, info: RouteInfo) {
///         guard case let .detail(id) = route else { return }
///         itemID = id
///     }
/// }
/// ```
///
/// - Important: Do not touch `view` in `configure`; it would load the view too early.
@MainActor
public protocol RouteConfigurable: AnyObject {
    /// The route type this page accepts.
    associatedtype RouteType: Route
    /// Configures the page from a route. Called once, before the view loads.
    func configure(with route: RouteType, info: RouteInfo)
}

extension RouteConfigurable {
    /// Type-erased entry point. Returns `false` when the route is not a `RouteType`.
    func applyRoute(_ route: any Route, info: RouteInfo) -> Bool {
        guard let typed = route as? RouteType else { return false }
        configure(with: typed, info: info)
        return true
    }
}

/// A module's registration entry point for the routes and deeplinks it handles.
///
/// ```swift
/// public enum DemoModule: RouteModule {
///     public static func register(in navigator: Navigator) {
///         navigator.register(DemoRoute.self) { _ in DemoDetailViewController() }
///         navigator.registerDeeplink(host: "demo") { url in DemoRoute(url: url) }
///     }
/// }
///
/// // List every module explicitly at launch; there is no runtime scanning.
/// Navigator.shared.install([DemoModule.self, SettingsModule.self])
/// ```
@MainActor
public protocol RouteModule {
    /// Registers this module's routes and deeplinks.
    static func register(in navigator: Navigator)
}
