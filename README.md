# To Do

A minimal to-do list for your Mac. Write down what's next, tick it off, and watch the days fill in on your streak heatmap. It lives in your Dock and your menu bar.

## Download (Mac)

1. Grab **`ToDo-1.0.dmg`** from the [latest release](https://github.com/o1ie12/ToDo/releases/latest).
2. Open it and drag **To Do** into **Applications**.
3. The first time you open it, macOS will block it (see below). After that it opens normally.

Requires macOS 13 or later.

### "To Do can't be opened" — is it safe?

Yes. macOS shows this warning for any app that isn't registered with Apple's paid developer program; it doesn't mean anything is wrong with the app. To Do is:

- **Open source** — every line of code is in this repo, and you can build it yourself (see below).
- **Private** — your tasks are stored only on your Mac. Nothing is uploaded or tracked. The only thing it loads from the internet is its font (from Google Fonts).
- **Tiny** — about 170 KB, no installers, no background services.

**To open it the first time:**

1. Double-click **To Do** in Applications. macOS says it can't be opened — click **Done** (or **OK**).
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about "To Do" and click **Open Anyway**, then confirm with your password or Touch ID.

On macOS 14 (Sonoma) and earlier you can instead **right-click** the app → **Open** → **Open**.

<details>
<summary>Prefer the Terminal?</summary>

```sh
xattr -cr "/Applications/To Do.app"
```

This removes the "downloaded from the internet" flag so macOS stops asking.
</details>

## Using it

- **Enter** to add · **checkbox** to complete · **double-click** to edit · **✕** to delete.
- Tasks you finish stay crossed off for the rest of the day, then move into your history.
- The heatmap shows how many tasks you finished each day (brighter = more, up to 10). Click a day to see what you did.
- **Menu bar:** click the ☑ icon or press **⌥⌘T** anywhere. Right-click it for **Open To Do**, **Open at Login** and **Quit**.
- **Settings** (bottom of the list): font size, light/dark, and menu bar layout — *Full* or *Minimal* (just your list, with a button to slide out your streak and history).

## Web version

Open `index.html` in any browser, or use https://o1ie12.github.io/ToDo/. In Safari, **File → Add to Dock** installs it like an app. The web version keeps its own list, separate from the Mac app.

## Build it yourself

Needs Xcode Command Line Tools (`xcode-select --install`).

```sh
./mac/build.sh      # builds mac/build/To Do.app
./mac/package.sh    # builds mac/build/ToDo-<version>.dmg
```

## License

MIT — free to use, change and share.
