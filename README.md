<div align="center">

# Kekasatori

**Turn videos, papers, and articles into study material on your Mac.**

[**⬇️ Download for macOS**](https://github.com/harikanthl/kekasatori/releases/latest/download/Kekasatori.dmg) · [Website](https://harikanth.site/projects/kekasatori) · [Privacy](https://harikanth.site/kekasatori/privacy) · [Terms](https://harikanth.site/kekasatori/terms)

</div>

---

Kekasatori takes a source you want to learn from (a YouTube lecture, an arXiv / PubMed / DOI paper, a web article, or a multi-chapter book) and turns it into a study pack you can actually work through. It is native, local-first, and free.

This repository holds the **full source**, the release downloads, and the auto-update feed. Kekasatori is open source under the MIT license.

## Install

1. Download [**Kekasatori.dmg**](https://github.com/harikanthl/kekasatori/releases/latest/download/Kekasatori.dmg) and open it.
2. Drag **Kekasatori** into your Applications folder.
3. Launch it. The app is notarized by Apple, so it opens with no security warnings.

Kekasatori keeps itself up to date automatically, and you can check for updates any time from the app menu.

**Requirements:** macOS 15.5 or later, Apple Silicon or Intel.

## What it does

- **Import anything.** A YouTube link, an arXiv / PubMed / DOI paper, a web article, or a book.
- **Study packs.** Clean transcripts, summaries, structured notes, flashcards, key concepts, and mind maps generated from the source.
- **A grounded AI tutor.** Chat about the material and get answers drawn from your document through retrieval, not guesswork.
- **A workshop to think in.** A built-in Excalidraw canvas, a notebook kept with each source, and animated Manim explainers for math and formulas.
- **Search YouTube in the app.** Find a video by name, no link needed.
- **Download or stream.** Keep media offline in a searchable library, or stream it.

## Private by default

This is the part we care about most. If your Mac supports Apple Intelligence, the whole experience, including the tutor, runs **on-device**. No account, no sign-up, no server, and nothing about what you study leaves your machine. If you want a larger model, you can bring your own key for Claude, GPT, Gemini, or DeepSeek, and even then your queries go only to the provider you chose. Keys are stored in the macOS Keychain.

See the [Privacy Policy](https://harikanth.site/kekasatori/privacy) and [Terms](https://harikanth.site/kekasatori/terms).

## Building from source

Requirements: Xcode 16 or later, macOS 15.5+.

1. Clone the repo and open `MuseDrop.xcodeproj`. (The Xcode target keeps the internal codename **MuseDrop**; the product is Kekasatori.)
2. The bundled `yt-dlp` and universal `ffmpeg` binaries are **not committed** (see `.gitignore`). Drop them into `MuseDrop/Resources/bin/`. The app also fetches and updates `yt-dlp` at runtime.
3. Build and run the `MuseDrop` scheme.
4. Optional: math animations require a local [Manim](https://www.manim.community/) + LaTeX install.

To produce a signed, notarized release, see [`Scripts/package-and-notarize.sh`](Scripts/package-and-notarize.sh) and [`Scripts/sparkle-release.md`](Scripts/sparkle-release.md).

## License

The Kekasatori source is released under the [MIT License](LICENSE).

The **distributed app** also bundles third-party components under their own licenses, including **FFmpeg (GPL)** and **yt-dlp (The Unlicense)**. FFmpeg runs as a separate executable (a subprocess), so it does not affect the MIT licensing of this source; see [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

## Notes

- You are responsible for ensuring your use of any third-party source complies with that service's terms and with applicable copyright law.

---

<div align="center">
Built by <a href="https://harikanth.site">Harikanth Lingutla</a>.
</div>
