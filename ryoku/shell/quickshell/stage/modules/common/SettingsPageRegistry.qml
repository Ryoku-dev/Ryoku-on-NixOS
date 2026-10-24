pragma Singleton
import Quickshell
Singleton {
    id: root
    function pageIndexById(pageId) { return -1; }
    function sectionIndexById(pageId, sectionId) { return -1; }
    function pageById(pageId) { return null; }
}
