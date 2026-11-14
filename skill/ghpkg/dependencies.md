# Dependencies

Nothing goes into `depends=` or `optdepends=` until the user has confirmed it.
Your job is to find the candidates, say where each came from, and ask.

## Where candidates come from

Use every source, and keep track of which one each candidate came from:

1. **Upstream's own list:** `metadata.depends` and `metadata.optdepends` from `ghpkg describe`.
   - From a `.zst` they're Arch names already.
   - From a `.deb` they're Debian names: translate them (below).
2. **Linked libraries:** `libraries.needed` in `describe --json`. Each library the programs link to has the installed package that owns it (`owner`). An owner that isn't in upstream's list is a candidate.
3. **The AUR's PKGBUILD** for the same app, if there is one.
4. **Libraries loaded at runtime.** When `describe` warns that the programs link only to the basic C libraries, they load more at runtime (`dlopen`). Nothing in the package lists those.
   - The AUR's PKGBUILD is the best guide.
   - Otherwise reason from what the app is. Rust GUI apps (winit) typically need `libxkbcommon`, `wayland`, `libx11`, `libxcursor`, `libxi`, `libxrandr`, `libglvnd` and `vulkan-icd-loader`.
   - Tell the user plainly that this part is a guess, and why.
5. **Upstream marks every display or GPU library optional.** Some upstream packages list `wayland`, `libx11`, `libglvnd`, `mesa` or `vulkan-driver` only in `optdepends`. The app can't start without at least one display library and one GPU library, so say so. Propose making the ones this session uses required: `wayland` on a Wayland desktop such as Omarchy or GNOME (check `$XDG_SESSION_TYPE`), `libx11` and its X11 libraries on X11, and `libglvnd` or `vulkan-icd-loader` for the GPU, depending on what the program loads. Leave the others optional.

Leave out what Arch packages never list:
- the basic libraries' packages (`glibc`, and `gcc-libs` or its parts `libgcc` and `libstdc++`), but only when upstream left them out too
- packages already pulled in by another dependency (only if you're sure)
- build tools

## Dependencies the official repos don't have

`describe` warns when upstream lists a dependency that the official repos don't have (`unavailable_depends` in `--json`). pacman would refuse to install the package. For each one:
- **Renamed or replaced:** an old name such as `libsoup`, where the program actually links `libsoup-3.0.so` from `libsoup3`. Propose the package that owns the library the program links to (`libraries.needed`).
- **On the AUR only:** pacman can't install it by itself. Propose it as optional, saying it's from the AUR, unless the app is useless without it; then ask.
- **Nowhere:** propose leaving it out, and say why.

## Translating Debian names

A Debian name is rarely the Arch name. For each one:

- **Libraries** (`libgtk-3-0`, `libwebkit2gtk-4.1-0`): find the Arch package that ships the library file.
  - Installed already: `pacman -Qo /usr/lib/<libfile>`.
  - Not installed: `pacman -F <libfile>`, after `sudo pacman -Fy` (the user runs that).
- **Common mappings:**

  | Debian | Arch |
  |---|---|
  | `libc6` | `glibc` |
  | `libgcc-s1` | `libgcc` (part of `gcc-libs`) |
  | `libstdc++6` | `libstdc++` (part of `gcc-libs`) |
  | `libgtk-3-0` | `gtk3` |
  | `libwebkit2gtk-4.1-0` | `webkit2gtk-4.1` |
  | `libayatana-appindicator3-1` | `libayatana-appindicator` |
  | `libnss3` | `nss` |
  | `libasound2` | `alsa-lib` |
  | `libsecret-1-0` | `libsecret` |
  | `libnotify4` | `libnotify` |
  | `libxss1` | `libxss` |
  | `libxtst6` | `libxtst` |
  | `xdg-utils` | `xdg-utils` |

- **Alternatives** (`a | b`): pick the Arch package for the first one that exists on Arch.
- **Version constraints** (`libc6 (>= 2.31)`): drop them. An Arch system is newer than any Debian minimum.
- **No Arch equivalent:** say so, and propose leaving it out.

## Showing the user

One table, then a question. For example:

| Dependency | Why | Installed? |
|---|---|---|
| `gtk3` | upstream (`libgtk-3-0`), linked | yes |
| `webkit2gtk-4.1` | upstream (`libwebkit2gtk-4.1-0`), linked | yes |
| `libayatana-appindicator` | upstream | no: installing would pull it in |
| `wayland` | AUR PKGBUILD; likely loaded at runtime (guess) | yes |

Print the table in your reply, then ask what to keep, remove or add, and which entries should be optional. A question tool can't show a table, so the table goes in the message before the question.
Write `optdepends=` entries as `'package: what it's for'`.

Check what's installed with `pacman -T <names...>`: it prints the ones nothing installed satisfies.
