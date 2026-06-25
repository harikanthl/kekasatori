# Third-Party Software & Licenses

Kekasatori bundles and depends on the following third-party software. This notice
satisfies the attribution requirements of their respective licenses and must be
included in the distributed application (e.g. in an "Acknowledgements" / "About"
screen and alongside the download).

---

## Bundled command-line tools

### FFmpeg — GPL (IMPORTANT: source-offer obligation)
- Project: https://ffmpeg.org
- License: **GNU General Public License v3** (the bundled build includes
  GPL-licensed components such as libx264).
- The bundled binary is an **unmodified** universal (arm64 + x86_64) build
  obtained from https://ffmpeg.martin-riedl.de/ .

**Corresponding source.** Because FFmpeg is distributed under the GPL, Kekasatori
must make the corresponding source available. The complete corresponding source
for this exact build can be obtained from:
- https://ffmpeg.org/download.html (FFmpeg sources), and
- https://ffmpeg.martin-riedl.de/ (the build configuration used).

> **Written offer:** For at least three (3) years, the Kekasatori author will, on
> request, provide a complete machine-readable copy of the corresponding source
> code for the bundled FFmpeg build. Contact: harikanth.ai@gmail.com.

The full text of the GNU GPL v3 is included in `licenses/GPL-3.0.txt`.

### yt-dlp
- Project: https://github.com/yt-dlp/yt-dlp
- License: **The Unlicense** (public domain dedication). No attribution required,
  provided here for transparency.

> **User responsibility.** yt-dlp is a general-purpose media tool. Kekasatori users
> are solely responsible for ensuring their use complies with the terms of
> service of any site they access and with applicable copyright law. See the
> in-app notice and EULA.

---

## Swift package dependencies

| Package | Source | License |
|---|---|---|
| VecturaKit | https://github.com/rryam/VecturaKit | MIT |
| Lottie (lottie-ios) | https://github.com/airbnb/lottie-ios | Apache 2.0 |
| swift-argument-parser | https://github.com/apple/swift-argument-parser | Apache 2.0 |

> Verify each license string against the version resolved in
> `MuseDrop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
> (the Xcode project keeps the internal codename "MuseDrop")
> before shipping; copy each project's `LICENSE` into `licenses/`.

---

## Bundled web assets

### Excalidraw
- Project: https://github.com/excalidraw/excalidraw
- License: **MIT**
- A built copy of the Excalidraw editor is embedded for the in-app canvas.

---

## Apple frameworks
SwiftUI, AppKit, FoundationModels, Speech, PDFKit, and other Apple frameworks
are used under the Apple SDK license and require no third-party attribution.

---

### Action items before release
- [x] Add `licenses/GPL-3.0.txt` (full GPL v3 text).
- [ ] Copy each SPM dependency's `LICENSE` file into `licenses/`.
- [ ] Surface this notice in an in-app **Acknowledgements** view and link it from
      the website download page.
- [x] Replaced the x86_64-only FFmpeg with a **universal (arm64+x86_64)** build
      (ffmpeg.martin-riedl.de) so Apple Silicon Macs don't need Rosetta.
