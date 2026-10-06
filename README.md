# Aidoku - Fork
This Aidoku Fork is primarily focussed around modernizations to the UI, implementing features according to my personal preferences and improving support and usage of private libraries (especially Komga). This fork isn’t necessarily a replacement for Aidoku and most people will likely still prefer the original, but if your preferences align with mine this fork might be up your alley.

This Fork of Aidoku was initially made to make some changes and enhancements that tailored towards my personal preferences, but this quickly spiraled out of control. At the time of writing this fork made over 25 improvements, ranging from small design tweaks to the ability to mark items as favorites, and a completely redesigned pinned item system. A full list of changes can be found below.

Even though this fork was primarily meant as a private project for private use, I am fully open to some of these changes being integrated into the main Aidoku branch. 

Some changes I made are currently non-configurable as I never planned for this to be much of a public project, changes I made later in the project are mostly configurable. Commits are unfortunately also quite a mess because I didn't really care about them much because of it being, again, a private project I started mostly for fun, which is why most commits were made and summarized by AI, often after multiple unrelated changes had been made.

<img width="25%" alt="Library" src="https://github.com/user-attachments/assets/ce209e69-2913-437f-a8c0-ef217b80a999" />
<img width="25%" alt="Info" src="https://github.com/user-attachments/assets/219baa5c-c80a-4db5-84b9-70de552906fc" />
<img width="25%" alt="Reader" src="https://github.com/user-attachments/assets/f4cbd8b7-efa9-4c12-83a8-733c885f241e" />


## List of changes:
_NOTE: This is the list of changes when the first build released, more changes can be found for each release in the releases section_

### Library
- Added a continue reading section, including extra compatibility and syncing in combination with Komga.
- Modernized the look of covers/posters.
- Removed the title on top of covers.
- Modernized the look of the unread/download badge.
- Added the ability to mark items as favorite, including a filter and pinned title option.
- Added configurable current-page previews in library context menus.
- Added the ability to hide covers for NSFW titles and show a generic cover instead.
- Improved cover loading, covers load almost instantly now.
- Optimized memory usage.
- Added option to grayscale finished titles.

### Pins
- Added more configurable pinned title types.
- Added optional section subtitles.
- Added option to have pinned titles sit in the library grid continuously, without any gab or spacing between them and the rest of the library.
- Added optional horizontally scrolling pinned row for the grid layout.
- Added an option to keep pinned titles in the normal Library section also.
- Added configurable filter ignoring for pinned titles.
- Added an in-library pin selector dropdown when section subtitles are enabled.
- Added empty pinned-section placeholder when section subtitles are enabled.
- Added page-preview caching for long-pressing library items.
- Added Pinned Titles seelection to the Library menu.

### Filters
- Added more (configurable) library filters, mostly focused at personal libraries like Komga.
  - Added a Caught Up filter.
  - Added a Source filter, shown only when multiple sources are present.
  - Added a configurable Genre filter, shown genres can be configured and support custom aliases.
- Added configurable two-state/three-state behavior for Content Rating, Collection, Category, and Source.
- Sorting now toggles ascending/descending by selecting the same sort option again, with direction shown only for the active option similar to some Apple apps like Files.

### Reader
- Modernized the look and feel of the reader with a new Apple Books-inspired thumbnail-style scrubber.
- Option to show reading progress as a percentage instead of page count for webtoons.
- Option for UI elements to hide automatically when the reader is opened.
- Optimized and improved how the reader loads pages, fixing the issue of pages taking a long time to load (mostly relevant for webtoons).
- The transition screen in between chapters now follows the reader background settings you pick.

### Miscellaneous
- Added spotlight support for searching library items.
- Added continue reading/pins to the iOS Home Screen long press menu.
- Browse, History and Favorites can be placed either in Settings or as dedicated tab-bar tabs.
- Added option to move settings to a top bar button.
- Updates was moved from the Library top bar into Settings.
- Added a dedicated Favorites view (either in settings or as a tab bar item).
- Added tab-bar scroll-to-top.
- Removed the refresh popup, when manually triggered by pulling down, the spinner now stays visible until the refresh finished.
- Slightly changed the look of the browse view.
- Added default sort options for chapters.
- Added option to show page count in chapter lists (for compatible sources)
- Changed how chapters are displayed in the chapters list.
- Added an option to use a FlareSolverr server to resolve source Cloudflare challenges.
- Improved some animations.
- Added the option to disable search history.
- Probably more I forgot about.
- Dropped support for older iOS versions because it would go against the philosophy of the fork to add fallback options for unsupported APIs and features, and I deemed it unnecessary to put time into this as this is still mostly a personal project. 


AI disclosure: some more complex changes were made with the help of Codex, changes were audited and approved by me, a human.

Also note that this fork lacks community translations for its additional features, these will all be in English only.

# Aidoku - Original README

A free and open source manga reading application for iOS, iPadOS, and macOS.

<p>
	<img src="https://raw.githubusercontent.com/Aidoku/Website/refs/heads/main/static/images/library-noframe.png" width="25%" alt="Library">
	<img src="https://raw.githubusercontent.com/Aidoku/Website/refs/heads/main/static/images/source-noframe.png" width="25%" alt="Source">
	<img src="https://raw.githubusercontent.com/Aidoku/Website/refs/heads/main/static/images/reader-noframe.png" width="25%" alt="Reader">
</p>

## Features

- No ads
- Local file reading (CBZ)
- Built-in reading service providers (Komga, Kavita, Suwayomi)
- WASM external source system
- Downloads
- Tracker integration (AniList, MyAnimeList, etc.)
- OCR dictionary lookup

## Installation

For detailed installation instructions, check out [the website](https://aidoku.app).

### TestFlight

To join the TestFlight, you will need to join the [Aidoku Discord](https://discord.gg/kh2PYT8V8d).

### AltStore

We have an AltStore repo that contains the latest releases ipa. You can copy the [direct source URL](https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json) and paste it into AltStore. Note that AltStore PAL is not supported.

### Manual Installation

The latest ipa file will always be available from the [releases page](https://github.com/Aidoku/Aidoku/releases). Nightly ipas are also built on each commit, but it's not recommended to use these since they may have in-progress changes that could cause issues when updating later.

## Contributing

Aidoku is still in a beta phase, and there are a lot of planned features and fixes. If you're interested in contributing, I'd first recommend checking with me on [Discord](https://discord.gg/kh2PYT8V8d) in the app development channel.

This repo (excluding translations) is licensed under [GPLv3](https://github.com/Aidoku/Aidoku/blob/main/LICENSE), but contributors must also sign the project [CLA](https://gist.github.com/Skittyblock/893952ff23f0df0e5cd02abbaddc2be9). Essentially, this just gives me (Skittyblock) the ability to distribute Aidoku via TestFlight/the App Store, but others must obtain an exception from me in order to do the same. Otherwise, GPLv3 applies and this code can be used freely as long as the modified source code is made available.

### Translations

Interested in translating Aidoku? We use [Weblate](https://hosted.weblate.org/engage/aidoku/) to crowdsource translations, so anyone can create an account and contribute!

Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).
