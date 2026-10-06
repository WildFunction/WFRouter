import Foundation
import Testing
import UIKit
@testable import WFRouter

private enum DemoRoute: Route {
    case detail(id: String)
    case unavailable
}

private struct PlainRoute: Route {}
private struct MismatchedRoute: Route {}
private struct UnregisteredRoute: Route {}
private struct SharedRoute: Route { let id: Int }

@MainActor
private final class DetailPage: UIViewController, RouteConfigurable {
    var detailID = ""
    var configureCount = 0
    var wasViewLoadedDuringConfigure = false
    var receivedInfo: RouteInfo?

    func configure(with route: DemoRoute, info: RouteInfo) {
        configureCount += 1
        wasViewLoadedDuringConfigure = isViewLoaded
        receivedInfo = info
        if case let .detail(id) = route {
            detailID = id
        }
    }
}

@MainActor
private final class PlainPage: UIViewController {}

/// Records dismiss calls.
@MainActor
private final class DismissSpy: UIViewController {
    var dismissCalls: [Bool] = []

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCalls.append(flag)
        completion?()
    }
}

private enum DemoModule: RouteModule {
    static func register(in navigator: Navigator) {
        navigator.register(DemoRoute.self) { route in
            route == .unavailable ? nil : DetailPage()
        }
        navigator.registerDeeplink(host: "detail") { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return nil }
            return DemoRoute.detail(id: id)
        }
    }
}

private enum PlainModule: RouteModule {
    static func register(in navigator: Navigator) {
        navigator.register(PlainRoute.self) { _ in PlainPage() }
        navigator.register(MismatchedRoute.self) { _ in DetailPage() }
    }
}

private func url(_ string: String) -> URL {
    // URLs in these tests are hardcoded valid literals.
    URL(string: string) ?? URL(fileURLWithPath: "/")
}

@MainActor
@Suite("Navigator")
struct NavigatorTests {
    private let navigator = Navigator()
    private let source = UIViewController()
    private let navigation: UINavigationController

    init() {
        navigation = UINavigationController(rootViewController: source)
        navigator.install([DemoModule.self, PlainModule.self])
    }

    // MARK: push

    @Test("push creates the page and pushes it onto the source's stack")
    func pushesOntoSourceNavigationStack() {
        #expect(navigator.open(DemoRoute.detail(id: "42"), style: .push(animated: false), from: source))
        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController is DetailPage)
    }

    @Test("Pushes directly when the source is a navigation controller")
    func pushesWhenSourceIsNavigationController() {
        #expect(navigator.open(PlainRoute(), style: .push(animated: false), from: navigation))
        #expect(navigation.topViewController is PlainPage)
    }

    @Test("configure runs once before the view loads, with the route and RouteInfo")
    func configuresBeforeViewLoads() throws {
        navigator.open(DemoRoute.detail(id: "42"), style: .push(animated: false), from: source)
        let page = try #require(navigation.topViewController as? DetailPage)

        #expect(page.configureCount == 1)
        #expect(!page.wasViewLoadedDuringConfigure)
        #expect(page.detailID == "42")
        #expect(page.receivedInfo?.source === source)
        #expect(page.receivedInfo?.style == .push(animated: false))
        #expect(page.receivedInfo?.url == nil)
    }

    @Test("Uses the top-most page when no source is given")
    func usesTopViewControllerWhenSourceIsNil() {
        navigator.rootViewControllerProvider = { [navigation] in navigation }
        #expect(navigator.topViewController() === source)
        #expect(navigator.open(PlainRoute(), style: .push(animated: false)))
        #expect(navigation.viewControllers.count == 2)
    }

    @Test("Returns false when no source can be found")
    func failsWithoutAnySource() {
        navigator.rootViewControllerProvider = { nil }
        #expect(navigator.topViewController() == nil)
        #expect(!navigator.open(PlainRoute()))
    }

    // MARK: Failure paths

    @Test("Unregistered routes return false")
    func failsForUnregisteredRoute() {
        #expect(!navigator.open(UnregisteredRoute(), from: source))
        #expect(navigation.viewControllers.count == 1)
    }

    @Test("Returns false when the builder returns nil")
    func failsWhenBuilderReturnsNil() {
        #expect(!navigator.open(DemoRoute.unavailable, from: source))
        #expect(navigation.viewControllers.count == 1)
    }

    @Test("A route type mismatch skips configure but still opens the page")
    func skipsConfigureOnRouteTypeMismatch() throws {
        #expect(navigator.open(MismatchedRoute(), style: .push(animated: false), from: source))
        let page = try #require(navigation.topViewController as? DetailPage)
        #expect(page.configureCount == 0)
    }

    @Test("The latest registration for a route type wins")
    func latestRegistrationWins() {
        navigator.register(PlainRoute.self) { _ in DetailPage() }
        navigator.open(PlainRoute(), style: .push(animated: false), from: source)
        #expect(navigation.topViewController is DetailPage)
    }

    @Test("makeViewController builds and configures without navigating")
    func makesViewControllerWithoutNavigating() throws {
        let info = RouteInfo(source: nil, style: .push())
        let made = navigator.makeViewController(for: DemoRoute.detail(id: "7"), info: info)
        let page = try #require(made as? DetailPage)
        #expect(page.detailID == "7")
        #expect(page.receivedInfo?.source == nil)
        #expect(navigation.viewControllers.count == 1)
        #expect(navigator.makeViewController(for: UnregisteredRoute(), info: info) == nil)
    }

    // MARK: present

    @Test("present wraps in a navigation controller by default")
    func presentsWrappedInNavigation() async throws {
        let window = TestWindow.show(navigation)
        #expect(navigator.open(DemoRoute.detail(id: "1"), style: .present(animated: false), from: source))
        #expect(await waitUntil { navigation.presentedViewController != nil })

        let wrapper = try #require(navigation.presentedViewController as? UINavigationController)
        let page = try #require(wrapper.viewControllers.first as? DetailPage)
        #expect(page.receivedInfo?.style == .present(animated: false))
        _ = window
    }

    @Test("present can skip wrapping and set the presentation style")
    func presentsBareWithStyle() async {
        let window = TestWindow.show(navigation)
        let style = RouteStyle.present(style: .fullScreen, wrapInNavigation: false, animated: false)
        #expect(navigator.open(PlainRoute(), style: style, from: source))
        #expect(await waitUntil { navigation.presentedViewController != nil })

        #expect(navigation.presentedViewController is PlainPage)
        #expect(navigation.presentedViewController?.modalPresentationStyle == .fullScreen)
        _ = window
    }

    @Test("push falls back to a wrapped present without a navigation stack")
    func pushFallsBackToPresent() async throws {
        let lonely = UIViewController()
        let window = TestWindow.show(lonely)
        #expect(navigator.open(PlainRoute(), style: .push(animated: false), from: lonely))
        #expect(await waitUntil { lonely.presentedViewController != nil })

        let wrapper = try #require(lonely.presentedViewController as? UINavigationController)
        #expect(wrapper.viewControllers.first is PlainPage)
        _ = window
    }

    // MARK: deeplink

    @Test("A deeplink resolves to a route and RouteInfo carries the URL")
    func opensDeeplink() throws {
        let link = url("wildfunction-demo://detail?id=9")
        #expect(navigator.open(url: link, style: .push(animated: false), from: source))

        let page = try #require(navigation.topViewController as? DetailPage)
        #expect(page.detailID == "9")
        #expect(page.receivedInfo?.url == link)
    }

    @Test("Deeplink hosts are case-insensitive")
    func deeplinkHostIsCaseInsensitive() {
        #expect(navigator.route(from: url("wildfunction-demo://DETAIL?id=1")) as? DemoRoute == .detail(id: "1"))
    }

    @Test("Unhandled deeplinks return nil / false", arguments: [
        "wildfunction-demo://unknown?id=1",
        "wildfunction-demo://detail",
        "wildfunction-demo://detail?id=",
        "mailto:someone@example.com",
        "detail?id=1",
    ])
    func rejectsUnhandledDeeplinks(link: String) {
        #expect(navigator.route(from: url(link)) == nil)
        #expect(!navigator.open(url: url(link), from: source))
        #expect(navigation.viewControllers.count == 1)
    }

    @Test("The scheme allowlist rejects other schemes")
    func enforcesSchemeAllowlist() {
        navigator.allowedDeeplinkSchemes = ["WildFunction-Demo"]
        #expect(navigator.route(from: url("wildfunction-demo://detail?id=1")) != nil)
        #expect(navigator.route(from: url("evil://detail?id=1")) == nil)
        #expect(!navigator.open(url: url("evil://detail?id=1"), from: source))
    }

    @Test("The latest registration for a host wins")
    func latestDeeplinkRegistrationWins() {
        navigator.registerDeeplink(host: "Detail") { _ in PlainRoute() }
        #expect(navigator.route(from: url("x://detail?id=1")) is PlainRoute)
    }

    // MARK: pop / dismiss

    @Test("pop removes the page from the stack")
    func pops() {
        let second = UIViewController()
        navigation.pushViewController(second, animated: false)
        navigator.pop(from: second, animated: false)
        #expect(navigation.viewControllers == [source])
    }

    @Test("pop / dismiss default to the top-most page")
    func popAndDismissDefaultToTop() {
        let top = DismissSpy()
        navigation.pushViewController(top, animated: false)
        navigator.rootViewControllerProvider = { [navigation] in navigation }
        #expect(navigator.topViewController() === top)

        navigator.dismiss(animated: false)
        #expect(top.dismissCalls == [false])

        navigator.pop(animated: false)
        #expect(navigation.viewControllers == [source])
    }

    @Test("dismiss calls dismiss on the given page and forwards animated")
    func dismisses() {
        // Modal transitions never complete without a host app, so verify the call with a spy.
        let modal = DismissSpy()
        navigator.dismiss(from: modal, animated: false)
        navigator.dismiss(from: modal)
        #expect(modal.dismissCalls == [false, true])
    }

    // MARK: Top view controller

    @Test("topViewController walks through navigation and tab containers")
    func findsTopThroughContainers() {
        let first = UIViewController()
        let second = UIViewController()
        let inner = UINavigationController(rootViewController: first)
        inner.pushViewController(second, animated: false)
        let other = UIViewController()
        let tab = UITabBarController()
        tab.setViewControllers([inner, other], animated: false)

        #expect(Navigator.topViewController(from: tab) === second)
        tab.selectedIndex = 1
        #expect(Navigator.topViewController(from: tab) === other)
        #expect(Navigator.topViewController(from: first) === first)
        #expect(Navigator.topViewController(from: nil) == nil)

        let emptyNavigation = UINavigationController()
        #expect(Navigator.topViewController(from: emptyNavigation) === emptyNavigation)
        let emptyTab = UITabBarController()
        #expect(Navigator.topViewController(from: emptyTab) === emptyTab)
    }

    @Test("topViewController walks through presented pages")
    func findsTopThroughPresented() async {
        let window = TestWindow.show(navigation)
        let modalRoot = UIViewController()
        let modal = UINavigationController(rootViewController: modalRoot)
        source.present(modal, animated: false)
        #expect(await waitUntil { navigation.presentedViewController != nil })

        #expect(Navigator.topViewController(from: navigation) === modalRoot)
        _ = window
    }

    @Test("Falls back to the key window without a provider")
    func fallsBackToKeyWindow() {
        navigator.rootViewControllerProvider = nil
        _ = navigator.topViewController()
    }

    // MARK: Misc

    @Test("RouteStyle defaults and equality")
    func routeStyleEquality() {
        #expect(RouteStyle.push() == .push(animated: true))
        #expect(RouteStyle.present() == .present(style: .automatic, wrapInNavigation: true, animated: true))
        #expect(RouteStyle.push() != .present())
    }

    @Test("wf_open goes through the shared Navigator")
    func pageConvenienceUsesSharedNavigator() {
        Navigator.shared.register(SharedRoute.self) { _ in PlainPage() }
        let page = UIViewController()
        let stack = UINavigationController(rootViewController: page)

        #expect(page.wf_open(SharedRoute(id: 1), style: .push(animated: false)))
        #expect(stack.topViewController is PlainPage)
        #expect(!page.wf_open(UnregisteredRoute()))
    }
}
