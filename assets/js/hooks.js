// LiveView hooks. Registered on the LiveSocket in app.js.

// Fires a one-time "lazy_load" event to the owning LiveView the first time the
// element is actually visible. Tabbed layouts (tab_components.ex) hide inactive
// tabs with Alpine's x-show, so a table in a hidden tab defers its data queries
// until the user opens that tab. Tab switches update location.hash (tabs.js),
// which is what re-triggers the visibility check.
//
// The hook element must keep its id and phx-hook attribute across ALL render
// states of the LiveView: LiveView only mounts hooks on newly added elements,
// so if a reconnect patches the un-loaded state onto an existing element the
// hook wouldn't re-mount. Instead the surviving hook instance gets the
// reconnected() callback and re-fires (the server remounts un-loaded).
export const LazyTab = {
  mounted() {
    this.fired = false
    this.onHashChange = () => setTimeout(() => this.maybeLoad(), 0)
    window.addEventListener('hashchange', this.onHashChange)
    this.maybeLoad()
  },
  reconnected() {
    this.fired = false
    this.maybeLoad()
  },
  maybeLoad() {
    if (this.fired) return

    // offsetParent is null while this element or any ancestor is display: none
    if (this.el.offsetParent === null) return

    this.fired = true

    // pushEvent rejects (or throws) while the LiveView is disconnected —
    // un-set fired so the next hashchange or reconnected() retries
    try {
      const push = this.pushEvent('lazy_load', {})
      if (push && typeof push.catch === 'function') {
        push.catch(() => (this.fired = false))
      }
    } catch (_e) {
      this.fired = false
    }
  },
  destroyed() {
    window.removeEventListener('hashchange', this.onHashChange)
  }
}
