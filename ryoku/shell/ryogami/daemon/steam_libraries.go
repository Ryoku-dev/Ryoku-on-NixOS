package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Steam keeps the list of its libraries in steamapps/ and mirrors it under config/.
// The stamp changes whenever Steam rewrites the file, which it does when a library
// or an install moves.
func libraryFoldersFile(root string) (path, stamp string) {
	for _, p := range []string{
		filepath.Join(root, "steamapps", "libraryfolders.vdf"),
		filepath.Join(root, "config", "libraryfolders.vdf"),
	} {
		if fi, err := os.Stat(p); err == nil && fi.Mode().IsRegular() {
			return p, fmt.Sprintf("%s|%d|%d", p, fi.ModTime().UnixNano(), fi.Size())
		}
	}
	return "", root
}

// steamLibraryDirs lists the root library first, then every other library the file
// names, in Steam's own order.
func steamLibraryDirs(root, vdfPath string) []string {
	dirs := []string{root}
	if vdfPath == "" {
		return dirs
	}
	b, err := os.ReadFile(vdfPath)
	if err != nil {
		return dirs
	}
	doc, err := parseVDF(b)
	if err != nil {
		return dirs
	}
	seen := map[string]bool{}
	if canon, err := wkCanonPath(root); err == nil {
		seen[canon] = true
	}
	for _, dir := range libraryFolderPaths(doc) {
		canon, err := wkCanonPath(dir)
		if err != nil || seen[canon] {
			continue
		}
		seen[canon] = true
		dirs = append(dirs, dir)
	}
	return dirs
}

// Current Steam writes each library as an object with a path; clients before 2021
// wrote the path as the numbered key's value.
func libraryFolderPaths(doc map[string]interface{}) []string {
	folders, _ := doc["libraryfolders"].(map[string]interface{})
	type numbered struct {
		n    int
		path string
	}
	var found []numbered
	for key, value := range folders {
		n, err := strconv.Atoi(key)
		if err != nil {
			continue
		}
		var path string
		switch v := value.(type) {
		case string:
			path = v
		case map[string]interface{}:
			path, _ = v["path"].(string)
		}
		if path != "" && filepath.IsAbs(path) {
			found = append(found, numbered{n, path})
		}
	}
	sort.Slice(found, func(i, j int) bool { return found[i].n < found[j].n })
	out := make([]string, len(found))
	for i, f := range found {
		out[i] = f.path
	}
	return out
}

// Wallpaper Engine's Workshop downloads land in the library it is installed to,
// often a second drive. Without an install, a library that already holds
// downloads wins, then the root.
func pickWeLibrary(dirs []string) string {
	for _, dir := range dirs {
		if fileExists(filepath.Join(dir, "steamapps", "appmanifest_"+workshopAppID+".acf")) {
			return dir
		}
	}
	for _, dir := range dirs {
		if dirExists(filepath.Join(dir, "steamapps", "workshop", "content", workshopAppID)) {
			return dir
		}
	}
	return dirs[0]
}

const (
	vdfEnd = iota
	vdfText
	vdfOpen
	vdfClose
)

type vdfReader struct {
	src []byte
	pos int
}

// parseVDF reads Valve's text KeyValues: quoted or bare tokens, nested braces and
// // comments. Keys fold to lower case because Steam matches them that way.
func parseVDF(b []byte) (map[string]interface{}, error) {
	r := vdfReader{src: b}
	return r.object(false)
}

func (r *vdfReader) object(nested bool) (map[string]interface{}, error) {
	out := map[string]interface{}{}
	for {
		key, kind, err := r.token()
		if err != nil {
			return nil, err
		}
		switch kind {
		case vdfEnd:
			if nested {
				return nil, fmt.Errorf("vdf: unclosed block")
			}
			return out, nil
		case vdfClose:
			if !nested {
				return nil, fmt.Errorf("vdf: unexpected }")
			}
			return out, nil
		case vdfOpen:
			return nil, fmt.Errorf("vdf: block without a key")
		}
		value, kind, err := r.token()
		if err != nil {
			return nil, err
		}
		switch kind {
		case vdfText:
			out[strings.ToLower(key)] = value
		case vdfOpen:
			child, err := r.object(true)
			if err != nil {
				return nil, err
			}
			out[strings.ToLower(key)] = child
		default:
			return nil, fmt.Errorf("vdf: %q has no value", key)
		}
	}
}

func (r *vdfReader) token() (string, int, error) {
	for r.pos < len(r.src) {
		c := r.src[r.pos]
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			r.pos++
		case c == '/' && r.pos+1 < len(r.src) && r.src[r.pos+1] == '/':
			for r.pos < len(r.src) && r.src[r.pos] != '\n' {
				r.pos++
			}
		case c == '{':
			r.pos++
			return "", vdfOpen, nil
		case c == '}':
			r.pos++
			return "", vdfClose, nil
		case c == '"':
			return r.quoted()
		default:
			start := r.pos
			for r.pos < len(r.src) && !strings.ContainsRune(" \t\r\n{}\"", rune(r.src[r.pos])) {
				r.pos++
			}
			return string(r.src[start:r.pos]), vdfText, nil
		}
	}
	return "", vdfEnd, nil
}

func (r *vdfReader) quoted() (string, int, error) {
	r.pos++
	var sb strings.Builder
	for r.pos < len(r.src) {
		c := r.src[r.pos]
		r.pos++
		switch c {
		case '"':
			return sb.String(), vdfText, nil
		case '\\':
			if r.pos == len(r.src) {
				continue
			}
			e := r.src[r.pos]
			r.pos++
			switch e {
			case 'n':
				sb.WriteByte('\n')
			case 't':
				sb.WriteByte('\t')
			default:
				sb.WriteByte(e)
			}
		default:
			sb.WriteByte(c)
		}
	}
	return "", vdfEnd, fmt.Errorf("vdf: unterminated string")
}
