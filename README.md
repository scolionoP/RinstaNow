# <img src="./Resources/AppIcon.iconset/icon_128x128.png" width="64" height="64" style="margin-right:1rem;"> RinstaNow

> _リンちゃんなう！　リンちゃんなう！！　リンちゃんリンちゃんリンちゃんなう！！！_

A small native macOS desktop client for Instagram direct messages.

The app uses SwiftUI for a traditional macOS split-view interface and `URLSession` for Instagram web-session requests.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command line tools

## Build

```sh
swift build
```

Run the debug executable:

```sh
.build/debug/IGDMClient
```

Build a `.app` bundle:

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open ".build/release/RinstaNow.app"
```

## Features

- Native sidebar/detail conversation layout.
- Native message bubbles and composer.
- Inline rendering for common image and video attachments.
- Refresh, session, and sign-out commands.
- Stores an imported Instagram cookie header in local app preferences.
- Carries forward `Set-Cookie` changes from Instagram responses.
- Reads conversations through Instagram's web Direct endpoints.
- Uses an optional WebKit login window to capture cookies and browser tokens, while keeping the main client native.
- Sends messages through a browser-shaped `IGDirectTextSendMutation` GraphQL request template.

## Notes

Instagram does not provide a general public Direct Messages API for personal desktop clients. This project emulates an authenticated browser session by sending the same kind of cookies and headers Instagram's web app uses.

To use it, open the Session sheet and click **Login Window...**. Sign into Instagram there, navigate through any challenge or 2FA screens, then click **Use This Session**. The app captures WebKit cookies and page tokens into the native client.

The manual cookie field and **Import HAR...** button remain as debugging fallbacks. HAR import looks for a `200` response from `IGDirectTextSendMutation` and stores the form fields and browser headers as the send template.

If Instagram returns HTTP 401 with `require_login`, stop using the client for a few minutes and sign back in through the browser. Instagram may invalidate a copied session when it decides the request pattern does not match the browser session closely enough.

## Acknowledgements

Icon art by [ゆこ](https://www.pixiv.net/en/artworks/10768453)
