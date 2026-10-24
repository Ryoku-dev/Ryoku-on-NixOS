package main

func init() {
	// The filter bar's mute toggle flips this default; it takes effect on what is playing now too.
	watchSetting("wallpaperMute", func(d *daemon, _ string, v interface{}) {
		mute := wallAudioDefaults().mute
		if b, ok := v.(bool); ok {
			mute = b
		}
		d.setAudio(&mute, nil, nil)
	})
}
