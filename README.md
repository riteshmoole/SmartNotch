# SmartNotch

<img src="docs/icon.png" width="96" align="right" alt="SmartNotch icon">

### [⬇️ Download SmartNotch for Mac](https://github.com/riteshmoole/SmartNotch/releases/latest/download/SmartNotch.zip) · [Website](https://riteshmoole.github.io/SmartNotch/)

**Your MacBook notch, but useful.** SmartNotch turns the notch into a Dynamic Island-style surface. Hover, click, or press **⌃⌥Space** and it opens to show:

- **Now Playing:** artwork, scrub bar, play/pause/skip, and volume for Music, Spotify, and browser video/audio, with Keep Awake, Focus, Mirror, and one-tap timers right underneath
- **File Shelf:** drag files onto the notch to park them, drag them out anywhere, or AirDrop them
- **Clipboard history:** recent text and images, with passwords skipped automatically
- **Utilities:** CPU, memory, and Wi-Fi at a glance
- **Mirror:** a camera preview to check yourself before a call
- **Live activities** beside the notch while it's closed: music playing, a timer counting down, or "In a call · Zoom" (once the call is answered; also FaceTime, Phone, Teams, WhatsApp and more)
- **Charging animation:** plug in and the notch flashes "Charging" with your battery filling up in green. Unplug and it shows "Unplugged" with your current charge (turn it off in Settings)
- **Volume HUD:** replaces the macOS volume overlay with one in the notch (on by default; turn it off in Settings)
- **Themes:** Liquid Glass Light and Liquid Glass Dark (Apple's glass look, from clear to frosted with a slider), five solid themes with optional glow, plus custom themes as simple JSON files

<p align="center"><img src="docs/screenshots/media.png" width="640" alt="SmartNotch showing Now Playing"></p>

No notch (external monitor, Mac mini)? SmartNotch draws a floating pill instead.

Free, open source (MIT), and private: **no accounts, no analytics, nothing leaves your Mac.**

## Install

**Requirements:** a Mac with Apple Silicon (M1 or newer), macOS 14 Sonoma or later.

### Option 1: one command (no security prompt)

Open Terminal and paste:

```sh
curl -fsSL https://riteshmoole.github.io/SmartNotch/install.sh | bash
```

It downloads the latest release, checks it's signed by SmartNotch's own certificate, installs it in Applications and opens it. Downloads made with `curl` aren't flagged as "from the internet", so macOS doesn't ask you to approve the app. The script is [docs/install.sh](docs/install.sh) if you want to read it first.

### Option 2: download the app

1. [Download SmartNotch.zip](https://github.com/riteshmoole/SmartNotch/releases/latest/download/SmartNotch.zip). Safari unzips it for you. In other browsers, double-click the ZIP in Downloads.
2. Drag **SmartNotch** from Downloads into **Applications**.
3. Open SmartNotch from Applications. macOS will say it can't verify the app. Click **Done** (not Move to Trash).
4. Go to **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to "SmartNotch was blocked". Confirm with Touch ID or your password.

You only do this once. Updates install from inside the app and never ask again. *Got "SmartNotch.dmg Not Opened"?* That's the old download format, which macOS blocks before it opens. Download the ZIP above instead. *Why the warning?* SmartNotch is a free project that isn't signed with a paid ($99/yr) Apple Developer certificate, so macOS can't vouch for it. The full source is right here if you want to check it or build it yourself.

## Updating

SmartNotch checks GitHub for a new version when it starts and once a day. When one is out, a red dot appears on the ⚙️ gear in the open notch, and the menu bar icon gets an **Update Available** item. Click either to see what's new, then click **Install Update**. SmartNotch downloads the new version, checks it's signed with the same certificate, replaces itself and reopens. There's no security prompt, and your settings and permissions carry over.

If it can't update itself (for example, it's running from Downloads, or your account can't change apps in Applications), it says why. Then click **Download**, quit SmartNotch, drag the new one into Applications and choose **Replace**, or run the install command again.

*On 0.1.5 or older?* Install Update arrived in 0.1.6, so update by hand one last time.

Prefer no network at all? Turn off **Settings → General → Check for updates once a day**.

## Permissions: only when you use the feature

SmartNotch asks for nothing at first launch.

| Feature | Permission | When it's asked |
|---|---|---|
| Mirror (camera preview) | Camera | First time you open the Mirror tab |
| Volume HUD (on by default) | Accessibility | Right after the welcome screen (say no to keep the macOS overlay) |
| Music/Spotify fallback | Automation | Only if full media detection stops working on a future macOS |

SmartNotch **never** asks for Location, Full Disk Access, or Screen Recording.

## Privacy

- Clipboard history is kept **in memory only** by default. Items that password managers mark as concealed are never recorded, and you can exclude apps or clear it with one click. Saving text history to disk is opt-in.
- The camera runs **only** while the Mirror tab is visible and stops the moment the notch closes. Nothing is recorded.
- Shelf files are stored in `~/Library/Application Support/SmartNotch/Shelf` and cleared automatically (24 h by default).
- The "In a call" indicator only checks *whether* your mic or camera is busy while a call app is open. It never sees who you're talking to.
- The notch is hidden from screen sharing and recordings by default.
- The only network requests are the update check (a plain download of the latest release info from GitHub, which sends nothing about you or your Mac; you can turn it off) and downloading the update when you click Install Update.

## Known limits (honest list)

- **Now Playing** uses a workaround for a private Apple framework ([mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)). A macOS update can break it. If that happens, SmartNotch falls back to Music and Spotify only, and says so in the app instead of showing a blank panel. Support policy: fixes are attempted within two weeks of a macOS release that breaks it.
- **No notification mirroring** (Messages banners, caller names). Apple doesn't allow it.
- **AirDrop** reaches Apple devices and only some Android phones. There's no AirDrop to Windows.
- **Focus toggle** needs a one-time Shortcut. SmartNotch walks you through it.
- Not on the Mac App Store. The App Store's sandbox forbids the techniques a notch app needs.

## Build from source

Needs only Apple's Command Line Tools (`xcode-select --install`). Full Xcode isn't required.

```sh
./Scripts/build-app.sh          # → build/SmartNotch.app
open build/SmartNotch.app
./Scripts/package-zip.sh        # → build/SmartNotch-<version>.zip (the download)
```

```
Sources/SmartNotch/   the app (App, Notch, Views, Providers, Theme)
Resources/            Info.plist, built-in themes, app icon
ThirdParty/           vendored mediaremote-adapter (BSD-3)
Scripts/              build, icon, and packaging scripts
docs/                 the download page (GitHub Pages)
```

## License

MIT. See `LICENSE`. Third-party components are listed in `THIRD_PARTY_NOTICES.md`.
