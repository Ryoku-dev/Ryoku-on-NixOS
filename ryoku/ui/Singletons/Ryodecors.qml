pragma Singleton
import QtQuick
import Quickshell

// Where the shipped decor art set lives on a user box: <Pictures>/ryodecors
// (Paths.picturesDir, so ~/Imágenes/ryodecors on a Spanish desktop). The
// installer seeds it and `ryoku doctor` keeps it current, so it sits beside
// Wallpapers and livewalls where a user can see and swap it. Decor and Placard
// resolve their baked art through `dir`; a custom pick keeps its own absolute
// path, so it never routes through here.
Singleton {
    readonly property string dir: "file://" + Paths.picturesDir + "/ryodecors/"
}
