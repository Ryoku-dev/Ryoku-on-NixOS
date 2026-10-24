package main

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestFillDimsStaticPNG(t *testing.T) {
	p := filepath.Join(t.TempDir(), "w.png")
	img := image.NewRGBA(image.Rect(0, 0, 321, 123))
	img.Set(0, 0, color.RGBA{R: 1, G: 2, B: 3, A: 255})
	f, err := os.Create(p)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(f, img); err != nil {
		f.Close()
		t.Fatal(err)
	}
	f.Close()

	var e Entry
	fillDims(&e, scanned{wpType: "static", src: p})
	if e.Width != 321 || e.Height != 123 {
		t.Fatalf("dims = %dx%d, want 321x123", e.Width, e.Height)
	}
}

func TestFillDimsMissingFileLeavesZero(t *testing.T) {
	var e Entry
	fillDims(&e, scanned{wpType: "static", src: "/no/such/file.png"})
	if e.Width != 0 || e.Height != 0 {
		t.Fatalf("dims = %dx%d, want 0x0 when the source cannot be read", e.Width, e.Height)
	}
}
