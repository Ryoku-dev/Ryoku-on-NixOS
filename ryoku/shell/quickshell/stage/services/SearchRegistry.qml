pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell

/**
 * The search box the hosted ii settings pages highlight against.
 *
 * Upstream ran these pages inside its own Settings window, whose search field
 * indexed every section and asked each one to scroll-and-highlight when its
 * title matched. Ryoku hosts the pages in the widget inspector and the Stage
 * Editor, neither of which has that search field, so the registry stays empty
 * and the highlight never fires. The property exists so the vendored pages
 * load; a future in-page search would write it here.
 */
Singleton {
    property string currentSearch: ""
}
