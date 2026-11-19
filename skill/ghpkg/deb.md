# Packaging a .deb

A `.deb` is an `ar` archive holding `control.tar*` (metadata and maintainer
scripts) and `data.tar*` (the files). makepkg unpacks the `.deb` itself, so
`data.tar*` is already in `$srcdir` when `package()` runs. The work is in
three places: translating the dependencies, translating any maintainer
scripts, and fixing the layout.

## What to take from `ghpkg describe`

- `metadata.name`, `metadata.url`: as for a `.zst`. `aur_same_app` too: those packages go in `conflicts=`, and no other AUR names.
- `metadata.description`: the first line of the control file's description. It becomes `pkgdesc`, with " (from the upstream GitHub release)" after it, as for a `.zst`. If it's a slogan rather than a description of what the app does ("Less chaos. More flow."), use the GitHub repo's description (`ghpkg inspect` shows it), or write a short plain one, and say so when you show the PKGBUILD. Leave out emoji.
- `metadata.licenses` is empty: a `.deb`'s control file has no licence field. Look at `usr/share/doc/<name>/copyright` in the package, or the GitHub repo's licence (`ghpkg inspect` shows it).
- `metadata.depends` and `metadata.optdepends` are **Debian names**. Translate each one; see `dependencies.md`.
- `scripts`: `preinst`, `postinst`, `prerm`, `postrm`, if any.
- `warnings`: what needs a decision or a layout fix. Each is `{code, text}`: show the user the `text`, and go by the `code` (such as `opt_without_bin` or `setuid`), which stays the same when the wording changes.

## The PKGBUILD

Start from `templates/PKGBUILD.deb`. The placeholders are the same as in
`zst.md`, except there's no `_file`: the source is the `.deb` itself. Write
the tag in the link the way `inspect`'s "Download links use the tag" line
says (`v$pkgver` in these examples).

```bash
source=("$url/releases/download/v$pkgver/myapp_${pkgver}_amd64.deb")
```

If the file name has no version in it (Stremio Service's is `stremio-service_amd64.deb`), give the download a versioned name:

```bash
source=("myapp-$pkgver.deb::$url/releases/download/v$pkgver/myapp_amd64.deb")
```

## Layout fixes

`describe` warns about each of these. Propose each fix to the user and apply
only the ones they agree to, in `package()` after the `bsdtar` line:

| Warning | Fix |
|---|---|
| Programs in `/opt` with nothing in `/usr/bin` | `mkdir -p "$pkgdir/usr/bin"` then `ln -s "/opt/App Name/app" "$pkgdir/usr/bin/app"` (Steam ROM Manager needed this) |
| `/usr/share/doc` | Optional: `rm -rf "$pkgdir/usr/share/doc"`. It holds Debian changelogs and the copyright file |
| `/etc/apt`, `/usr/share/lintian`, `/usr/share/menu` | Delete them: they're for Debian only. An `/etc/apt` file would add an apt repository |
| Icon folders the hicolor theme doesn't know | Move the icons to the right size folder. Trust `describe` on this: it checks the system's own theme list, and folders such as `256x256@2` (double resolution) are valid |
| Files with the setuid bit | Ask what they're for before keeping them. Electron's `chrome-sandbox` is the common case; Arch normally runs Electron without it |
| Files outside `/usr` and `/opt` | Look at each. `/etc` files the user may edit belong in `backup=` |

## Maintainer scripts

Debian's maintainer scripts don't map one-to-one onto pacman's. Never copy one
as it is. Show it to the user, explain what it does, and agree on a pacman
version:

| Debian | pacman (`<pkgname>.install`) |
|---|---|
| `postinst` with `configure` | `post_install()`, and `post_upgrade()` if it should run on updates too |
| `prerm` with `remove` | `pre_remove()` |
| `postrm` with `remove` or `purge` | `post_remove()` |
| `preinst` | `pre_install()` / `pre_upgrade()` |

Leave these out: pacman's own hooks already do them on Arch.
- `update-desktop-database`
- `gtk-update-icon-cache`
- `update-mime-database`
- `ldconfig`
- `systemctl daemon-reload`
- `glib-compile-schemas`

Anything about `apt`, `dpkg`, `debconf` or `update-alternatives` has no Arch equivalent. Tell the user what it was for and drop it.

## Checks before handing over

- `ghpkg test-build <name>` compares the files with the `.deb`'s `data.tar`. Expect differences only from the fixes the user agreed to, such as a deleted `usr/share/doc` or an added `usr/bin` link. Explain each one.
- Every Debian dependency was translated or deliberately left out, with the user's agreement.
