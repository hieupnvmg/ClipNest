<p align="center">
  <img src="Assets/AppIcon.png" width="96" alt="ClipNest app icon">
</p>

<h1 align="center">ClipNest</h1>

<p align="center">
  <strong>A clipboard history for your Mac.</strong><br>
  Find the link, screenshot, or snippet you copied earlier and paste it where you need it.
</p>

<p align="center">
  <a href="https://github.com/hieupnvmg/ClipNest/releases/latest"><strong>Download for Mac ↓</strong></a>
  &nbsp; · &nbsp;
  <a href="https://github.com/hieupnvmg/ClipNest/releases">Release notes</a>
  &nbsp; · &nbsp;
  <a href="https://github.com/hieupnvmg/ClipNest/issues">Feedback</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-18181B?style=flat-square" alt="macOS 13 or later">
  <img src="https://img.shields.io/badge/Mac-Apple%20Silicon-007AFF?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/github/v/release/hieupnvmg/ClipNest?style=flat-square&amp;label=release&amp;color=17803D" alt="Latest release">
</p>

![ClipNest demo showing the clipboard panel opening, filtering as you type, and selecting an item](docs/demo.gif)

<p align="center">
  <kbd>⇧⌘V</kbd> &nbsp; Open &nbsp; → &nbsp; Type to search &nbsp; → &nbsp; <kbd>Return</kbd> to paste
</p>

<table>
<tr>
<td width="50%" valign="top">
<h3>Your clipboard, ready to reuse</h3>
<p>Keep text, links, screenshots, colors, and file references together. Paste with formatting or choose plain text.</p>
</td>
<td width="50%" valign="top">
<h3>Links and IPs, collected for you</h3>
<p>Useful Links and IP Addresses gather standalone URLs and IPs automatically, including CIDR such as <code>1.1.1.1/32</code>. Create your own pinboards for notes and snippets.</p>
</td>
</tr>
<tr>
<td valign="top">
<h3>Share a snippet</h3>
<p>Right-click text and choose <strong>Push to pikab.in (1 week)…</strong> to get a shareable link. Anyone with the link can read it until it expires.</p>
</td>
<td valign="top">
<h3>Make it feel at home</h3>
<p>Choose your shortcut, transparency, and launch-at-login settings. Enjoy native Liquid Glass on macOS 26+, with a frosted appearance on earlier versions.</p>
</td>
</tr>
</table>

## Features in action

### Find a clip as you type

Start typing as soon as the panel opens. Matches at the beginning come first, with matching capitalization taking priority. Newer clips lead within each group.

![Searching for design in ClipNest shows a matching link and text snippet](docs/search-preview.png)

<table>
<tr>
<td width="40%" valign="top">
<h3>Generate a password</h3>
<p>Open <strong>Password</strong> beside the pinboards, choose 12–64 characters, and copy the result.</p>
<p>Toggle symbols, reveal the password, or generate another with one click. Copied passwords appear in history and are masked when protection is enabled.</p>
</td>
<td width="60%">
<img src="docs/password-preview.png" width="460" alt="Password generator with length, symbols, reveal, and copy controls">
</td>
</tr>
</table>

<details>
<summary>Light and dark screenshots</summary>

![ClipNest in light appearance](docs/preview.png)

![ClipNest search in dark appearance](docs/preview-dark.png)

</details>

## Get started

1. [Download the latest DMG](https://github.com/hieupnvmg/ClipNest/releases/latest), open it, and drag **ClipNest** into **Applications**.
2. Launch ClipNest and press **`⇧⌘V`** to open the clipboard panel. Start typing to search, use the arrow keys to choose an item, and press **Return** to paste.
3. To paste directly into other apps, enable ClipNest under **System Settings → Privacy & Security → Accessibility**. You can also choose **Copy Only** and paste with **`⌘V`**.

ClipNest runs on Apple Silicon Macs with macOS 13 or later. The current build is distributed without Apple notarization. If macOS blocks the first launch, see [Apple’s guidance on opening apps](https://support.apple.com/102445).

Already installed? Right-click the ClipNest menu bar icon and select **Check for Updates…**.

## Keyboard shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⇧⌘V` | Toggle the clipboard panel. You can change this shortcut in Preferences. |
| Type after opening | Search clipboard history |
| `←` `→` `↑` `↓` | Select an item |
| `Return` | Paste the selected item |
| `⌘1`–`⌘9` | Paste one of the first nine results |
| `⌘F` | Focus the search field |
| `Esc` | Close the panel |

## Clipboard privacy

Clipboard history stays on your Mac and requires no account. Sensitive-content protection is on by default and can mask recognized emails, phone numbers, payment card numbers, passwords, and tokens on screen. You can reveal a masked item for 15 seconds. ClipNest stores and pastes the original value, and masking provides no app-level encryption.

You can exclude apps, pause capture, or check how much disk space history uses. **Preferences → Clipboard Storage → Clear** deletes history, including pinned items, after confirmation. Original images load from disk on demand.

The **Push to pikab.in** action sends the selected item’s original text to PikaBin. Update checks and downloads use GitHub.

<details>
<summary>Build from source</summary>

On macOS, install Apple Command Line Tools and use Swift 5.9 or later. Native Liquid Glass requires a macOS 26 SDK or newer.

```sh
git clone https://github.com/hieupnvmg/ClipNest.git
cd ClipNest
./build.sh
../ClipNest.app/Contents/MacOS/ClipNest --self-test
```

The build creates `ClipNest.app` next to the repository. The self-test uses temporary data and a private clipboard. [Development notes](docs/DEVELOPING.md)

</details>

<p align="center">
  <a href="https://github.com/hieupnvmg/ClipNest/releases/latest"><strong>Download ClipNest</strong></a> &nbsp; · &nbsp; <a href="https://github.com/hieupnvmg/ClipNest/issues">Share feedback</a><br><br>
  Made for Mac by <a href="https://github.com/hieupnvmg">hieupn</a>.
</p>
