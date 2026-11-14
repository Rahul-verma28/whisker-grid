# Whisker Grid website

A static site served by **GitHub Pages** from this `docs/` folder. There's no build step: plain HTML and CSS.

| Page | URL | Used for |
|---|---|---|
| `index.html` | https://rahul-verma28.github.io/whisker-grid/ | Game homepage ("Website" in Play Console) |
| `privacy.html` | https://rahul-verma28.github.io/whisker-grid/privacy.html | **Privacy policy URL** in Play Console |
| `terms.html` | https://rahul-verma28.github.io/whisker-grid/terms.html | Terms of use |
| `app-ads.txt` | see the note below | AdMob ad verification |

## ⚠️ One thing to fix: the old custom domain redirect
The repo `Rahul-verma28.github.io` contains a `CNAME` file with `rahuldev.me`. Because of it, GitHub redirects **every** Pages site on this account to `rahuldev.me/...`. But rahuldev.me is hosted on Vercel, so the game site shows "not found" there.

To make the game site load at the URLs above:
1. Open https://github.com/Rahul-verma28/Rahul-verma28.github.io
2. Do **one** of these:
   - delete the `CNAME` file, or
   - go to **Settings → Pages** and clear the **Custom domain** field (or unpublish that site).

Your Vercel portfolio at rahuldev.me is not affected either way, because its DNS points to Vercel, not GitHub.

## app-ads.txt
AdMob looks for `app-ads.txt` at the **root** of the website listed on Google Play, for example `https://rahul-verma28.github.io/app-ads.txt` and not `/whisker-grid/app-ads.txt`. Pick one:
- copy `app-ads.txt` into the root of the `Rahul-verma28.github.io` repo (together with the CNAME fix above), **or**
- list `https://www.rahuldev.me` as the website on Google Play and add the same file to your Vercel portfolio's `public/` folder, so it's served at `https://www.rahuldev.me/app-ads.txt`.

The file contains your publisher line:
```
google.com, pub-9206798746776764, DIRECT, f08c47fec0942fa0
```

## Updating the site
Edit the files in `docs/`, then commit and push. Pages redeploys automatically in about a minute.
The "Get it on Google Play" buttons already point to
`https://play.google.com/store/apps/details?id=com.whiskergrid.puzzle`, which starts working once the app is published.
