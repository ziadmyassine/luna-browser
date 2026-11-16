//
//  InspectorStyle+Script.swift
//  Luna
//
//  What the inspector's restyle does that CSS cannot: Elements keeps its
//  search field out, full width under the tab bar, instead of behind ⌘F; and
//  the inspector's own close button fades it out before it goes.
//
//  It is WebKit's own find banner, so searching, the result count, the arrows
//  and ⌘F are all WebKit's. Escape, which hid it, clears it instead. The
//  script reaches into the inspector's own objects (`WI`, a view's `__view`)
//  and checks each before using it, so a WebKit that renames one leaves the
//  banner where WebKit puts it.
//

import Foundation

extension InspectorStyle {

    /// The sidebar's opacity half, which a docked inspector leaves on.
    private static let fadeOut = Int(Tokens.Motion.sidebarCollapseOpacity.duration * 1000)

    /// Safe to run any number of times: `WebInspector.restyle` sends it with
    /// every pass of the stylesheet. The first run installs a one-second check,
    /// because the Elements tab can be opened, closed and opened again, each
    /// time with a new banner.
    ///
    /// It also has the tab bar measure its tabs again. WebKit caches each tab's
    /// width to decide which fold into its overflow menu, and the cache was
    /// taken at WebKit's sizes, before this stylesheet made the tabs wider.
    ///
    /// Every way the frontend closes itself — its close button, its shortcuts
    /// — ends in `InspectorFrontendHost.closeWindow`, so that is where the
    /// fade goes; Luna's own ⌥⌘I fades the view instead
    /// (`ContentCardView.closeInspector`). The opacity comes back after, for a
    /// WebKit that shows the same page again.
    static let script = """
    (function () {
      if (window.__lunaInspector) return;
      window.__lunaInspector = true;
      var measured = false;
      function standSearch() {
        var host = document.querySelector('.content-view.tab.elements > .content-browser');
        var banner = host && host.__view && host.__view._findBanner;
        if (!banner || banner.__lunaStanding || !banner.targetElement || !banner.targetElement.parentNode) return;
        if (typeof banner.hide !== 'function' || typeof banner._inputFieldInput !== 'function') return;
        banner.__lunaStanding = true;
        banner.inputField.placeholder = 'Search — text, tag, attribute or selector';
        function show() {
          var target = banner.targetElement;
          if (!target || !target.parentNode) return;
          if (banner.element.parentNode !== target.parentNode) target.parentNode.insertBefore(banner.element, target);
          target.classList.add('showing-find-banner');
          banner.element.classList.add('showing', 'luna-pinned');
        }
        var hide = banner.hide.bind(banner);
        banner.hide = function () {
          if (banner.searchQuery) { banner.searchQuery = ''; banner._inputFieldInput(); }
          hide();
          show();
        };
        show();
        banner.dispatchEventToListeners(WI.FindBanner.Event.DidShow);
      }
      function fadeOnClose() {
        var host = window.InspectorFrontendHost;
        if (!host || host.__lunaFades || typeof host.closeWindow !== 'function') return;
        var close = host.closeWindow.bind(host);
        host.closeWindow = function () {
          var body = document.body;
          if (!body || matchMedia('(prefers-reduced-motion: reduce)').matches) return close();
          body.style.transition = 'opacity \(fadeOut)ms ease-out';
          body.style.opacity = '0';
          setTimeout(function () {
            close();
            setTimeout(function () { body.style.opacity = ''; body.style.transition = ''; }, 500);
          }, \(fadeOut));
        };
        host.__lunaFades = true;
      }
      function tick() {
        if (typeof WI === 'undefined') return;
        if (!measured && WI.tabBar && WI.tabBar.resetCachedWidths) {
          measured = true;
          WI.tabBar.resetCachedWidths();
          WI.tabBar.needsLayout();
        }
        standSearch();
        fadeOnClose();
      }
      setInterval(tick, 1000);
      tick();
    })();
    """
}
