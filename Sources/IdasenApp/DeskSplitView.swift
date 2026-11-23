import AppKit
import SwiftUI

/// Keeps native split-view sizing while letting the sidebar material define its edge.
struct DeskSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    var sidebarVisible: Bool
    var sidebar: Sidebar
    var detail: Detail

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        let splitView = DeskSplitContainer()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        controller.splitView = splitView

        let sidebar = NSSplitViewItem(viewController: host(sidebar, in: context.environment))
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 260
        sidebar.preferredThicknessFraction = 0.20
        sidebar.holdingPriority = .defaultHigh
        sidebar.isCollapsed = !sidebarVisible
        controller.addSplitViewItem(sidebar)
        controller.addSplitViewItem(NSSplitViewItem(viewController: host(detail, in: context.environment)))
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        let sidebarItem = controller.splitViewItems[0]
        let detailItem = controller.splitViewItems[1]
        (sidebarItem.viewController as? NSHostingController<AnyView>)?.rootView = hosted(sidebar, in: context.environment)
        (detailItem.viewController as? NSHostingController<AnyView>)?.rootView = hosted(detail, in: context.environment)
        let shouldCollapse = !sidebarVisible
        if sidebarItem.isCollapsed != shouldCollapse {
            sidebarItem.isCollapsed = shouldCollapse
        }
    }

    private func host<Content: View>(_ content: Content, in environment: EnvironmentValues) -> NSHostingController<AnyView> {
        let controller = NSHostingController(rootView: hosted(content, in: environment))
        // The window and split items own sizing so each page keeps the same viewport.
        controller.sizingOptions = []
        return controller
    }

    private func hosted<Content: View>(_ content: Content, in environment: EnvironmentValues) -> AnyView {
        AnyView(content.environment(\.self, environment))
    }
}

private final class DeskSplitContainer: NSSplitView {
    override var dividerColor: NSColor { .clear }

    override func drawDivider(in rect: NSRect) {}
}
