# Vifari

Vimium/Vimari for Safari without browser extension in pure Lua.

- Not a browser extension - works via accessability API, so most probably will work with
any Safari version despite past or future Plugin API changes. Theoretically, it
is even easily adjustable for other browsers. Works in all Safari parts - e.g. doesn't
stall on empty pages (plans are even to make `f`/`F` work on bookmarks and similar pages,
scrolling already works there).

- No Swift/XCode - only Lua. Just a single text file.

- No need for Apple Developer account, etc. No distribution.

- Fully trustable from security perspective, because it is FOSS with Lua readable by any programmer.
No keylogging risk and ok to run on sensitive sites with credentials/tokens/etc.

- A bonus - people who are interested in Vi bindings, most probably already know Lua to some extent.

This is a very early version, code is a bit messy, some minor bugs expected, but it is fully functional
on the level of Vimari at least. Plans are to keep it reasonably simple, so it will never be as
advanced as Vimium, but it should cover most of the daily needs for a Safari user (like me).
PRs and ideas are welcomed.

Initially, this was an attempt to make Vimari a bit better (e.g. by adding `yy` or `g1`).
But it became so hard with Swift (and Apple plugin distribution), and so easy with Hammerspoon and
Lua, that just for fun I tried to do `f` with marks in Hammerspoon/Lua (which is the core functionality)
and it worked so well, that I removed Vimari the next day.

There are some other Safari extensions that do vimming except Vimari, but despite being
more polished, they are closed source and thus raise security worries. To a point that
I can't use those on sites with any potential credentials (e.g. AWS, Heroku, etc.).
Which minimizes their usefulness and only creates anger of switching back&forth and using mouse.

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/) e.g. as `brew install hammerspoon`

2. Get this repo, either of:

  - clone this repo to `~/.hammerspoon/Spoons/Vifari.spoon`

  - clone to any other location like your projects folder and
    add symlink to `~/.hammerspoon/Spoons/Vifari.spoon`

  - just copy `init.lua` to `~/.hammerspoon/Spoons/Vifari.spoon/init.lua`

3. Add to your `~/.hammerspoon/init.lua`:
```lua
hs.loadSpoon("Vifari")
spoon.Vifari:start() -- this will add hooks. `:stop()` to remove hooks
```

4. After restarting Hammerspoon, you should see `V` in the menu bar when Safari is focused.
   hjkl (and other keys) should work.

5. Refresh local repo sometimes to get the latest version.

6. Enjoy!


## Usage

Vifari automatically detects "text input" fields, so when you *natutally* type something, most probably
it will not interfere. When you *naturally* are not in the text field, it will use Vi Normal mode binds.
This works rather smoothly, but may be not perfect for all cases.

If you need to disable Normal mode, press `i` - it will be in Insert mode till next `escape`.

If you want to totally disable Vifari do `spoons.Vifari:stop()` in hammerspoon console.

### Current binds:
```
h/j/k/l - scroll left/down/up/right
u/d - scroll half page up/down
gg/G - scroll to top/bottom
f - show marks and jump in same window
F - show marks and jump in new window
t - show marks and move mouse to the mark
q/w - prev/next tab
[] - back and forward in history
r - reload page
yy - copy current page URL to clipboard
yf - copy picked URL to clipboard
i - enter insert mode till next escape
g1-8 - go to tab 1-8
g9, g$ - go to last tab
escape - exit insert mode or abort any other multi-key combination
escape+escape (quickly) - forced unfocus from control from any place
```

All keys with modifiers (except shift) are passed through to Safari, thus most of the
native Safari key bindings will continue to work as expected.

### Menu bar

There is a menu bar with mode indicator:
```
V - Vifari mode
X - unfocused
g/f/F/t/y/... - or other symbols show multi-key combination start
```

### Tips

- If hjkl don't work, most probably mouse cursor is out of the scrollable area. Use `t` to navigate to some
  visible element and then use hjkl.

- `t` is very handy to switch scrollable areas on very complex pages.

- some sites are using invisible non-hidden text fields (to capture custom keystrokes?), which Vifari recognizes
  as valid text fields and auto-disables Normal mode. In such a case it helps to press `escape` so that this
  hidden field will loose focus, and continue in Normal mode. In very hard cases, use `escape+escape` to force
  unfocus from any place.

## Known issues

- Rarely it is a bit laggy (e.g. key pressed, but command is executed a bit later), but that's mostly
happens in times of Safari's unresponsiveness - e.g. processing a heavy page just at the moment.

## Possible next todo ideas

- Extend marks to bookmarks, reading list, etc. non-web items.
- Analog of `f` command but for toolbar, tabbar, etc.
- Bitwarden support by keypress

## Similar projects

- [Vimium](https://github.com/philc/vimium) - the best, but Chrome
- [Vimari](https://github.com/televator-apps/vimari) - Safari clone of Vimium, unfortunately outdated
- [Vimlike](https://www.jasminestudios.net/vimlike/) - nice but closed source, no info about developer

## License

MIT
