import AppKit
import Testing
@testable import Markv

@MainActor
@Test func nativeScrollIndicatorIsThinAndFollowsHoverState() {
    #expect(
        MarkvSlimScroller.scrollerWidth(
            for: .mini,
            scrollerStyle: .overlay
        ) == 5
    )

    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
    let configurator = SlimScrollConfiguratorView(frame: .zero)
    documentView.addSubview(configurator)
    scrollView.documentView = documentView

    configurator.isHovered = false
    configurator.configureScrollView()
    #expect(scrollView.verticalScroller is MarkvSlimScroller)
    #expect(scrollView.verticalScroller?.alphaValue == 0)

    configurator.isHovered = true
    configurator.configureScrollView()
    #expect(scrollView.verticalScroller?.alphaValue == 1)
}
