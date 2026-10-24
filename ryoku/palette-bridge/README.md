# Ryoku Palette Bridge

The Ryoku desktop package installs the bridge runtime on Arch, Void, and
Fedora. Open **Ryogami > Settings > Integrations** to set up and enable its
service, then configure the applications you want to follow the palette.
Installing the runtime does not enable its service or change applications.

The Zen extension source lives in `zen-extension/`. The directory also
contains `ryoku-zen-palette-1.0.3.xpi`, an AMO-signed, unlisted package of that
source. The bridge package ships both because its packaging copies this
directory to `/usr/share/ryoku/palette-bridge/`.

After installing the bridge package, open the signed add-on in Zen:

```sh
zen-browser /usr/share/ryoku/palette-bridge/zen-extension/ryoku-zen-palette-1.0.3.xpi
```

Approve the installation prompt. Zen accepts the signed XPI without developer
mode. The file can also be installed from `about:addons` using **Install Add-on
From File**.

The XPI was signed by Mozilla for the extension ID
`ryoku-zen-palette@local`, version `1.0.3`. To publish a later build, submit
the updated extension to Mozilla Add-ons for unlisted signing, then replace
the XPI alongside the updated extension source.

SHA-256: `92f1c390ab44a8b9f7f9e365a3ddb6e58a499d7e4ee0edcefda581f4cd5c6d8f`.
