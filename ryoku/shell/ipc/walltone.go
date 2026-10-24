package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
)

// walltone.go describes the wallpaper the way a Material role describes a
// panel: CIE L* per cell on an 8x8 grid, row-major from the top-left, plus the
// frame mean. Surfaces that float on the picture (the visualiser, a bare
// desktop widget) have no panel to contrast against, so without this they take
// whatever tone the scheme picked for a surface that is not there -- near-black
// on a light scheme, which is why the spectrum drew black bars.
//
// L* is the unit because a tone distance is a contrast budget in it: 40 apart
// clears 3:1, 50 apart clears 4.5:1. Material 3 builds its tonal palettes on
// the same rule, so this and the ramps agree by construction.
//
// Beside the mean grid sits a detail grid: the population standard deviation of
// each cell's sub-cell L* values. Same L* units, for the same reason -- a 40-L*
// spread inside one cell is a 3:1 swing of contrast under whatever floats there,
// so a widget that inks itself from one measured tone would fight the picture. A
// caller reads detail to find where the wallpaper is quiet (near 0) and drops
// its surface there; the mean grid then says which tone to ink against.

const wallToneCols, wallToneRows = 8, 8

// wallToneSub is the sub-cells-per-axis inside one cell. The picture is decoded
// once at wallToneCols*wallToneSub x wallToneRows*wallToneSub, so each cell owns
// wallToneSub*wallToneSub samples: enough to read a cell's spread, cheap enough
// to stay one ffmpeg call.
const wallToneSub = 4

// wallpaperTonePath is the map every wallpaper-floating surface watches.
func wallpaperTonePath() string {
	return filepath.Join(matugenCacheHome(), "ryoku", "wallpaper-tone.json")
}

// writeWallpaperTone samples pic into the map. A video is measured through the
// same still the palette is generated from, so both describe one frame. On
// failure the previous map stands: last wallpaper's tones still beat none.
func writeWallpaperTone(pic string) {
	if pic == "" || !isFile(pic) {
		return
	}
	if isVideo(pic) {
		frame := liveFrame(pic)
		if frame == "" {
			return
		}
		// This call happens for the wallpaper actually on screen, so it is the
		// one place allowed to move the stable poster pointer; previews of other
		// clips never repoint it.
		publishLivePoster(frame)
		pic = frame
	} else {
		// A still wallpaper: retire the pointer so no surface keeps sampling the
		// last clip's frame after the desktop moved on.
		_ = os.Remove(livePosterPath())
	}
	m, ok := wallToneMap(pic)
	if !ok {
		return
	}
	_ = writeJSONFile(wallpaperTonePath(), m)
}

// wallToneMap builds the published map for img in one decode: the mean-L* grid
// (unchanged in meaning and 8x8 shape), the per-cell detail grid, and the frame
// mean. Both writers -- the on-disk map and matugen's live preview -- route
// through here so the two never drift.
func wallToneMap(img string) (map[string]any, bool) {
	grid, detail, ok := wallToneMaps(img)
	if !ok {
		return nil, false
	}
	var sum float64
	for _, v := range grid {
		sum += v
	}
	return map[string]any{
		"cols":   wallToneCols,
		"rows":   wallToneRows,
		"lstar":  round2(sum / float64(len(grid))),
		"grid":   grid,
		"detail": detail,
	}, true
}

// wallToneMaps decodes img once, area-averaged, to a wallToneCols*wallToneSub
// square and reduces each 8x8 cell's sub-cells to its mean L* (grid) and the
// population standard deviation of that L* (detail). ffmpeg does the scaling, so
// png / jpeg / webp and a sampled video still all resolve through one path
// rather than splitting on what the stdlib decoders happen to read.
func wallToneMaps(img string) (grid, detail []float64, ok bool) {
	sc, sr := wallToneCols*wallToneSub, wallToneRows*wallToneSub
	out, err := runCommandOutput("ffmpeg", "-v", "error", "-i", img,
		"-vf", fmt.Sprintf("scale=%d:%d:flags=area", sc, sr),
		"-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-")
	if err != nil || len(out) < sc*sr*3 {
		return nil, nil, false
	}
	subL := make([]float64, sc*sr)
	for i := range subL {
		subL[i] = lstarFromY(relLuminance(out[i*3], out[i*3+1], out[i*3+2]))
	}
	grid, detail = wallToneReduce(subL)
	return grid, detail, true
}

// wallToneReduce turns a row-major buffer of sub-cell L* values (sc wide, sr
// tall) into the per-cell mean grid and detail grid. Split out from the decode
// so the cell geometry is testable without an image on disk.
func wallToneReduce(subL []float64) (grid, detail []float64) {
	sc := wallToneCols * wallToneSub
	n := wallToneCols * wallToneRows
	grid = make([]float64, n)
	detail = make([]float64, n)
	var sub [wallToneSub * wallToneSub]float64
	for cy := range wallToneRows {
		for cx := range wallToneCols {
			i := 0
			for sy := range wallToneSub {
				for sx := range wallToneSub {
					sub[i] = subL[(cy*wallToneSub+sy)*sc+cx*wallToneSub+sx]
					i++
				}
			}
			mean, sd := cellStats(sub[:])
			cell := cy*wallToneCols + cx
			grid[cell] = round2(mean)
			detail[cell] = round2(sd)
		}
	}
	return grid, detail
}

// cellStats reduces a cell's sub-cell L* samples to its mean tone and the
// population standard deviation of that tone. Population, not sample: these
// samples are the whole cell, not a draw from a larger set, so the spread it
// reports is the spread that is actually there.
func cellStats(vs []float64) (mean, stddev float64) {
	if len(vs) == 0 {
		return 0, 0
	}
	var sum float64
	for _, v := range vs {
		sum += v
	}
	mean = sum / float64(len(vs))
	var ss float64
	for _, v := range vs {
		d := v - mean
		ss += d * d
	}
	return mean, math.Sqrt(ss / float64(len(vs)))
}

// relLuminance is WCAG relative luminance: sRGB channels linearised, then the
// CIE Y weights. Not the 0.299/0.587/0.114 luma the smart light/dark pick uses;
// that runs on gamma-encoded values and misjudges the mid tones where a
// contrast call is close.
func relLuminance(r8, g8, b8 uint8) float64 {
	lin := func(v uint8) float64 {
		u := float64(v) / 255
		if u <= 0.04045 {
			return u / 12.92
		}
		return math.Pow((u+0.055)/1.055, 2.4)
	}
	return 0.2126*lin(r8) + 0.7152*lin(g8) + 0.0722*lin(b8)
}

// lstarFromY maps relative luminance to CIE L* (0..100).
func lstarFromY(y float64) float64 {
	if y <= 216.0/24389.0 {
		return y * 24389.0 / 27.0
	}
	return math.Cbrt(y)*116.0 - 16.0
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }
