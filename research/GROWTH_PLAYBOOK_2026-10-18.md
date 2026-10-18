# Growth playbook, 2026-10-18

Every item is a passive listing or a post that ROADMAP.md now permits. Do
them in this order; each one is an inbound link Google needs before anything
else works. Topics on both repositories are already set.

Status on 2026-10-18:

| Item | State |
|---|---|
| 1. awesome-mac | Open: jaywcjlove/awesome-mac#3583 |
| 2. open-source-mac-os-apps | Open: serhii-londar/open-source-mac-os-apps#1669 |
| 3. macmenubar.com | Maintainer only: the Tally form needs an app-domain email (no Gmail), three screenshots of the app in the real menu bar, and a reCAPTCHA |
| 4. awesome-swift-macos-apps | Open: jaywcjlove/awesome-swift-macos-apps#157 |
| 5. awesome-quantified-self | Blocked: the repository has pull requests and issues disabled; the entry is on the `add-ring-stats` branch of the fork |
| 6. Discussions | Created: #57 (pin it from the web UI, the API cannot), #58, #59 |
| 7. Oura email | Drafted in Gmail, not sent |
| 8. GIF and images | README images switched to WebP (61 KB and 161 KB, from 812 KB and 1.87 MB); the GIF needs a recording of the installed app |
| 9. r/ouraring | After the GIF and the next release |

Facts to keep straight everywhere: free, MIT, native Swift, macOS 14 or
later, Apple silicon and Intel, signed and notarized DMG or Homebrew
(`brew install --cask PetriLahdelma/ring-stats/ring-stats`), your own Oura
developer app, no server, no history on disk, ring battery with a 20%
nudge. Never say "quantified self" on the awesome-quantified-self list (their
rule), and never claim Oura endorsement.

## 1. awesome-mac (about 1 hour)

1. Fork https://github.com/jaywcjlove/awesome-mac and clone the fork.
2. In `README.md`, find `### Menu Bar Tools`. Entries are alphabetical; add
   after Repose:

   ```markdown
   * [Ring Stats](https://github.com/PetriLahdelma/ring-stats) - Oura ring Readiness, Sleep, Activity, heart rate, and battery in the menu bar, from your own Oura developer app with no server in between. [![Open-Source Software][OSS Icon]](https://github.com/PetriLahdelma/ring-stats) ![Freeware][Freeware Icon]
   ```

3. Add the same line, translated, in the same section of `README-zh.md`,
   `README-ja.md`, and `README-ko.md`:

   ```markdown
   * [Ring Stats](https://github.com/PetriLahdelma/ring-stats) - 在菜单栏显示 Oura 指环的 Readiness、睡眠、活动、心率和电量，通过你自己的 Oura 开发者应用直连，没有中间服务器。 [![Open-Source Software][OSS Icon]](https://github.com/PetriLahdelma/ring-stats) ![Freeware][Freeware Icon]
   * [Ring Stats](https://github.com/PetriLahdelma/ring-stats) - Oura リングの Readiness、睡眠、アクティビティ、心拍数、バッテリーをメニューバーに表示。自分の Oura 開発者アプリで直接接続し、中継サーバーはありません。 [![Open-Source Software][OSS Icon]](https://github.com/PetriLahdelma/ring-stats) ![Freeware][Freeware Icon]
   * [Ring Stats](https://github.com/PetriLahdelma/ring-stats) - Oura 링의 준비도, 수면, 활동, 심박수, 배터리를 메뉴 막대에 표시합니다. 자신의 Oura 개발자 앱으로 직접 연결하며 중간 서버가 없습니다. [![Open-Source Software][OSS Icon]](https://github.com/PetriLahdelma/ring-stats) ![Freeware][Freeware Icon]
   ```

4. One commit, one PR, title `Add Ring Stats to Menu Bar Tools`. Body: one
   sentence saying what it is and that all four READMEs are updated.

## 2. open-source-mac-os-apps (30 minutes)

1. Fork https://github.com/serhii-londar/open-source-mac-os-apps.
2. Edit `applications.json` only (not the README). Append to the array,
   keeping the file's key order:

   ```json
   {
     "title": "Ring Stats",
     "short_description": "Oura ring scores and battery in the menu bar, read through your own Oura developer app with no server of its own.",
     "categories": ["Menubar", "Medical"],
     "repo_url": "https://github.com/PetriLahdelma/ring-stats",
     "icon_url": "https://raw.githubusercontent.com/PetriLahdelma/ring-stats/main/Sources/RingStats/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png",
     "screenshots": ["https://raw.githubusercontent.com/PetriLahdelma/ring-stats/main/.github/assets/ring-stats-hero.png"],
     "official_site": "https://github.com/PetriLahdelma/ring-stats/releases/latest",
     "languages": ["Swift"]
   }
   ```

3. PR title `Add Ring Stats`.

## 3. macmenubar.com (15 minutes)

Form: https://macmenubar.com/submit-your-menu-bar-app/

- Name: Ring Stats
- Category: Health
- URL: https://github.com/PetriLahdelma/ring-stats/releases/latest
- Description: Your Oura ring's Readiness, Sleep, Activity, heart rate, and
  battery in the Mac menu bar. Native, open source, no server: data goes from
  Oura to your Mac and nowhere else. Free, signed and notarized, Apple
  silicon and Intel.
- Image: `.github/assets/ring-stats-hero.png`

## 4. awesome-swift-macos-apps (20 minutes)

1. Fork https://github.com/jaywcjlove/awesome-swift-macos-apps.
2. In `README.md`, section `## Menubar`, copy a neighbour's badge pattern
   and add:

   ```markdown
   - [Ring Stats](https://github.com/PetriLahdelma/ring-stats) ![GitHub stars](https://badgen.net/github/stars/PetriLahdelma/ring-stats) ![GitHub last commit](https://img.shields.io/github/last-commit/PetriLahdelma/ring-stats) - Oura ring scores and battery in the menu bar, fetched from Oura straight to your Mac with no server.
   ```

3. Same in `README-zh.md`. The maintainer posts each new entry on X.

## 5. awesome-quantified-self (15 minutes)

https://github.com/woop/awesome-quantified-self, section
`## Open Source Projects`, at the bottom of the category:

```markdown
- [Ring Stats](https://github.com/PetriLahdelma/ring-stats) - Oura ring Readiness, Sleep, Activity, heart rate, and battery in the macOS menu bar, read directly from Oura with no server (macOS).
```

If the PR endpoint is disabled, open an issue with the same line; their
contributing file allows it.

## 6. Seed Discussions (30 minutes)

https://github.com/PetriLahdelma/ring-stats/discussions, three threads:

1. Pinned, category General, title `Which ring and Mac are you running Ring
   Stats on?` Body: "Reply with your ring generation, Mac, macOS version, and
   whether Stress and Resilience show. This is how the Supported rings table
   in the README stays honest." First reply: your own setup.
2. Category General, title `Gen2 and Intel Mac reports wanted`. Body: link
   to the README's Supported rings table, say both are untested by you, and
   ask for one line per report.
3. Category Ideas, title `What would make the five-second glance better?`
   Body: link issues #28 (battery threshold), #34 (stat explanations), #35
   (release discovery) and ask what is missing.

## 7. The Oura email (15 minutes, then a 14-day wait)

To: api-support@ouraring.com, from the address on your developer portal
account. Subject: `Written confirmation request: voluntary funding for a
free open-source Oura viewer`.

> Hello,
>
> I maintain Ring Stats, a free, open-source macOS menu-bar viewer for a
> member's own Oura data: https://github.com/PetriLahdelma/ring-stats
>
> How it works: each user registers their own application in the Oura
> developer portal and authorizes it through OAuth, so there is no shared
> client, the 10-user limit does not apply, and Ring Stats has no server:
> data goes from the Oura API to the user's Mac and is held in memory only.
> There is no charge and nothing is unlocked by payment. Privacy policy:
> https://github.com/PetriLahdelma/ring-stats/blob/main/PRIVACY.md
>
> I would like written confirmation that accepting voluntary donations
> (GitHub Sponsors, Buy Me a Coffee) for such a client is consistent with
> the Oura API Terms. Until I hear back, the project shows no funding
> buttons.
>
> Thank you,
> Petri Lahdelma

Set a reminder for 2026-11-01. If there is no reply, the buttons stay off
and the next council decides whether to ask again.

## 8. The GIF and image compression (2 to 3 hours)

- Record 6 to 8 seconds: click the icon, popover opens in Holographic, move
  the pointer so the foil shifts, Escape. QuickTime screen recording of the
  popover region, then `ffmpeg -i in.mov -vf "fps=20,scale=680:-1" -loop 0
  ring-stats-holographic.gif`, target under 3 MB. Place it under the pitch in
  the README; keep the PNG as the social preview.
- Re-export `ring-stats-hero.png` and the two theme images at 1360 px wide
  as 8-bit PNG (`pngquant --quality 80-95`), target under 250 KB each; the
  README currently loads 2.7 MB above the fold.

## 9. The r/ouraring post (after 1 to 8)

Title: `Free, open-source Mac menu bar app for Oura scores and ring
battery (no server, your own Oura app)`. Body: three sentences on what it
shows, one on the no-server design and the two-minute setup, one on the
shutdown of Oura on the Web, the GIF, the GitHub link. Answer every comment
for 48 hours. Do not post the same day in more than one place.

## Measure

Two weeks after the last listing merges: downloads per release asset
(`gh api repos/PetriLahdelma/ring-stats/releases`), README traffic
referrers (`gh api repos/PetriLahdelma/ring-stats/traffic/popular/referrers`),
stars. The next council reads those three numbers first.
