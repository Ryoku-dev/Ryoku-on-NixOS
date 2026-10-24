// flatImageProvider adapts an extras category whose products are a single image
// the user drops into a ~/Pictures subfolder: decors into ryodecors (the Hub's
// Decor and Placard gallery reads it), launcher heroes into ryoku-launchers (the
// launcher settings picker reads it). Unlike the tree-installed categories such a
// product owns exactly one flat file, named by its id, so its installed state is
// simply whether that file exists. Each product ships a raw and a pre-baked
// dithered variant; the store's dither toggle picks which one lands.
package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

type flatImageProvider struct {
	category Category
	cache    *Cache
	dirPath  string
}

// newFlatImageProvider builds a flat-file image provider for one category,
// installing into ~/Pictures/<subdir>.
func newFlatImageProvider(category Category, subdir string, cache *Cache) flatImageProvider {
	if cache == nil {
		cache = newCache()
	}
	return flatImageProvider{category: category, cache: cache, dirPath: filepath.Join(picturesHome(), subdir)}
}

// The three flat-image catalogues share the Decor tab: decor art for the empty
// spaces, hero art for the launcher, and emblems for the fastfetch readout.
// They install into different Pictures folders because different surfaces read
// them, but the store browses them as one family of pictures.
func newDecorProvider(cache *Cache) flatImageProvider {
	return newFlatImageProvider(Category{
		ID:          "decors",
		Name:        "Decor",
		Group:       "make",
		Description: "Curated specimen art for the empty spaces across the Ryoku hub and apps.",
	}, "ryodecors", cache)
}

func newLauncherImageProvider(cache *Cache) flatImageProvider {
	return newFlatImageProvider(Category{
		ID:          "launcher-images",
		Name:        "Launcher images",
		Group:       "make",
		Description: "Curated hero art for the app launcher's header.",
	}, "ryoku-launchers", cache)
}

func newFastfetchEmblemProvider(cache *Cache) flatImageProvider {
	return newFlatImageProvider(Category{
		ID:          "fastfetch-emblems",
		Name:        "Fastfetch emblems",
		Group:       "make",
		Description: "Emblems for the terminal readout, sized for a fastfetch logo box.",
	}, "ryoemblems", cache)
}

func (p flatImageProvider) Category() Category { return p.category }

// installedPath is the flat file a product owns in its Pictures subfolder. The
// consuming surface lists that folder by bare filename, so a store install
// appears there with no further wiring.
func (p flatImageProvider) installedPath(id string) string {
	return filepath.Join(p.dirPath, id+".png")
}

func (p flatImageProvider) Load(ctx context.Context, refresh bool) ([]Item, SourceState, error) {
	entries, state, err := loadProductRegistry(ctx, p.cache, p.category.ID, refresh)
	if err != nil {
		return nil, state, err
	}
	items := make([]Item, 0, len(entries))
	for _, entry := range entries {
		item, err := productEntryItem(p.cache.base, p.category.ID, entry)
		if err != nil {
			return nil, state, err
		}
		// The raw (undithered) preview so the store's dither toggle can show both looks.
		item.ArtRaw = resolveAsset(p.cache.base, entry.Path, entry.PreviewRaw)
		// A flat-image product owns one file; its presence is the whole install record.
		if _, statErr := os.Stat(p.installedPath(entry.ID)); statErr == nil {
			item.Installed = true
			item.InstalledVersion = entry.Version
			item.UpdateAvailable = false
		}
		items = append(items, item)
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].Installed != items[j].Installed {
			return items[i].Installed
		}
		return items[i].Name < items[j].Name
	})
	return items, state, nil
}

func (p flatImageProvider) Install(ctx context.Context, id string) error {
	return p.InstallVariant(ctx, id, false)
}

// InstallVariant copies the chosen variant (dithered or raw) into the product's
// Pictures subfolder as one flat file. Both variants are PNG, so the installed
// file is always <id>.png regardless of the toggle.
func (p flatImageProvider) InstallVariant(ctx context.Context, id string, dither bool) error {
	entries, _, err := loadProductRegistry(ctx, p.cache, p.category.ID, false)
	if err != nil {
		return err
	}
	entry, err := findProductEntry(entries, id)
	if err != nil {
		return err
	}
	variant := "source.png"
	if dither {
		variant = "dither.png"
	}
	reportProgress(ctx, "download", 0, 0)
	data, _, err := p.cache.Fetch(ctx, path.Join(entry.Path, "content", variant), true)
	if err != nil {
		return fmt.Errorf("%s/%s: fetch %s: %w", p.category.ID, id, variant, err)
	}
	reportProgressNow(ctx, "download", int64(len(data)), int64(len(data)))
	reportProgressNow(ctx, "extract", 1, 1)
	if err := os.MkdirAll(p.dirPath, 0o755); err != nil {
		return err
	}
	reportProgressNow(ctx, "apply", 0, 1)
	return atomicWrite(p.installedPath(id), data, 0o644)
}

func (p flatImageProvider) Remove(_ context.Context, id string) error {
	if !productIDPattern.MatchString(id) {
		return fmt.Errorf("invalid %s id %q", p.category.ID, id)
	}
	if err := os.Remove(p.installedPath(id)); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// picturesHome mirrors the Hub singleton and CLI resolver, so a Store command
// launched outside the desktop session still follows user-dirs.dirs.
func picturesHome() string {
	home := os.Getenv("HOME")
	if d := normalizedPicturesHome(os.Getenv("XDG_PICTURES_DIR"), home); d != "" {
		return d
	}
	f, err := os.Open(filepath.Join(configHome(), "user-dirs.dirs"))
	if err == nil {
		defer f.Close()
		const key = "XDG_PICTURES_DIR="
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			line := strings.TrimSpace(sc.Text())
			if strings.HasPrefix(line, key) {
				if d := normalizedPicturesHome(strings.TrimPrefix(line, key), home); d != "" {
					return d
				}
			}
		}
	}
	return filepath.Join(home, "Pictures")
}

func normalizedPicturesHome(value, home string) string {
	v := strings.Trim(strings.TrimSpace(value), `"'`)
	switch {
	case v == "$HOME":
		v = home
	case strings.HasPrefix(v, "$HOME/"):
		v = filepath.Join(home, strings.TrimPrefix(v, "$HOME/"))
	}
	if !filepath.IsAbs(v) {
		return ""
	}
	v = filepath.Clean(v)
	if v == filepath.Clean(home) {
		return ""
	}
	return v
}
