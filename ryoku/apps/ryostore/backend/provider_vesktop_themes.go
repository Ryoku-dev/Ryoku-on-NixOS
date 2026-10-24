package main

import "context"

const vesktopThemesCategory = "vesktop-themes"

type vesktopThemesProvider struct {
	cache *Cache
}

func newVesktopThemesProvider(cache *Cache) vesktopThemesProvider {
	return vesktopThemesProvider{cache: cache}
}

func (vesktopThemesProvider) Category() Category {
	return Category{
		ID:          vesktopThemesCategory,
		Name:        "Vesktop themes",
		Group:       "wear",
		Description: "Install themes here, then enable them in Vesktop Settings > Vencord > Themes.",
	}
}

func (p vesktopThemesProvider) Load(ctx context.Context, refresh bool) ([]Item, SourceState, error) {
	entries, state, err := loadProductRegistry(ctx, p.cache, vesktopThemesCategory, refresh)
	if err != nil {
		return nil, state, err
	}
	items := make([]Item, 0, len(entries))
	for _, entry := range entries {
		item, err := productEntryItem(p.cache.base, vesktopThemesCategory, entry)
		if err != nil {
			return nil, state, err
		}
		items = append(items, item)
	}
	return items, state, nil
}

func (p vesktopThemesProvider) Install(ctx context.Context, id string) error {
	entries, _, err := loadProductRegistry(ctx, p.cache, vesktopThemesCategory, false)
	if err != nil {
		return err
	}
	entry, err := findProductEntry(entries, id)
	if err != nil {
		return err
	}
	return installProduct(ctx, p.cache, vesktopThemesCategory, entry)
}

func (vesktopThemesProvider) Remove(ctx context.Context, id string) error {
	return removeProduct(ctx, vesktopThemesCategory, id)
}
