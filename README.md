# To Do

A tiny, dependency-free todo list in a single HTML file. Tasks are saved in your browser's `localStorage`.

## Use it
- Open `index.html` in any browser, or use the hosted version at https://o1ie12.github.io/to-do/ (install it from Safari via File → Add to Dock).
- **Enter** to add · **checkbox** to complete · **double-click** to edit · **✕** to delete.
- Toggle light/dark in the top right.
- The heatmap shows tasks completed per day; click a day to see what you finished.

## Mac menu bar app
A tiny native wrapper (in `mac/`) puts the list in your menu bar.

```sh
./mac/build.sh
cp -R "mac/build/To Do.app" /Applications/
```

- Click the ☑ icon in the menu bar, or press **⌥⌘T** anywhere.
- Right-click the icon for **Open in Window**, **Open at Login** and **Quit**.
- Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

## License
MIT
