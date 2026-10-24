#!/usr/bin/env bash

# Shared parser for unresolved Git conflict markers.
ryoku_marker_hunks() {
  local file=$1

  LC_ALL=C awk '
    /^<<<<<<< / {
      if (inside) {
        print start ":" NR - 1
      }
      start = NR
      inside = 1
      separator = 0
      next
    }
    inside && /^=======/ {
      separator = 1
      next
    }
    inside && /^>>>>>>> / {
      if (separator) {
        print start ":" NR
      }
      inside = 0
      separator = 0
      next
    }
    END {
      if (inside) {
        print start ":" NR
      }
    }
  ' "$file"
}
