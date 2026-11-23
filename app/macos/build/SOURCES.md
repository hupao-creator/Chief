# Application icon source

[Chief's logo](../../../design/chief-logo.webp) is the shared 1024 × 1024
artwork for the repository README and the packaged Mac app. The generated
illustration shows a black skillet tossing symbols for Codex, Pi and Claude
Code, with warm gray motion marks on an ivory tile. The agent marks identify
their respective products. Padding outside the tile is transparent.

The full-surface loading mark uses the [high-toss motion study](../../../demos/chief-logo-loading/toss-variants/high.webp).
The shared UI bundle contains transparent 240 × 240 GIFs for [light](../Sources/Shared/PluginUI/Resources/ChiefStartupToss.gif) and [dark](../Sources/Shared/PluginUI/Resources/ChiefStartupTossDark.gif) appearances. Both show only the moving foreground over 80 frames at 40 ms per frame. The dark version adds a fine gray edge to the dark ink.

[`generate-app-icon.swift`](generate-app-icon.swift) resizes this artwork with
ImageIO and packages the representations with the macOS `iconutil` tool.

From the repository root, regenerate with the macOS command-line tools:

```sh
mkdir -p .build/app-icon
xcrun swiftc -module-cache-path .build/app-icon/ModuleCache \
  app/macos/build/generate-app-icon.swift -o .build/app-icon/generate
.build/app-icon/generate design/chief-logo.webp app/macos/build/AppIcon.icns
```

The iconset includes 16, 32, 128, 256 and 512 point images at 1× and 2×. PNG
encoding can vary across macOS toolchains; compare decoded pixels when checking
reproducibility across versions. Development, production and alpha packaging copy
this same `AppIcon.icns` to `Contents/Resources/AppIcon.icns`, referenced by
`CFBundleIconFile=AppIcon`. Regeneration changes the source asset; rebuild and
package the application to use it in a new bundle.

To inspect the encoded representations without launching or replacing an app:

```sh
iconutil --convert iconset --output .build/app-icon/preview.iconset \
  app/macos/build/AppIcon.icns
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  .build/app-icon/preview.iconset/icon_512x512@2x.png
```

Use a fresh output directory for each extraction. Inspect both the 1024-pixel
master and small Dock/Finder sizes; the outer padding must stay transparent.
