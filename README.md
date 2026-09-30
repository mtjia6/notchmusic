# NotchMusic

just a little thing i made for myself because i wanted it on my mac. not a product, not polished.

music player that lives in the notch. hover it → cover, controls, progress bar.
also has apple music search, and a script view for reading notes under the camera on calls.
no dock icon. settings = right-click the notch. quit = ♪ in the menu bar. start it again = spotlight → NotchMusic.

## run it

`./build.sh` — builds, installs to ~/Applications, kills the old one. then `open ~/Applications/NotchMusic.app`

⚠️ `swift build` does NOT update the app you're running. always use build.sh.

`NotchMusic --snapshot <dir>` dumps screenshots of every screen if you need them.

## setup (new mac)

- say yes when it asks to control Music
- import `Resources/NotchPlay Link.shortcut` — needed to play songs that aren't in your library (applescript can't, shortcuts can)

## where stuff is

- notch window, hover/click → `NotchWindowController`
- modes + sizes → `NotchViewModel`
- main UI + right-click menu → `NotchRootView`
- buttons, progress bar, cover → `Components`
- streaks → `LightSpeed`
- talking to Music → `MusicController`, `AppleScriptRunner`
- search → `CatalogSearch`
- script tabs → `Prompter`
- colors/animation → `Theme`, `ArtworkColor`, `Motion`
