# Packaging a .pkg.tar.zst

The release file is already an Arch package. The PKGBUILD only unpacks it into
`$pkgdir` under a new name, so pacman and ghpkg can manage it.
`ghpkg add <owner/repo>` does all of this on its own; this is for doing it
with the user by hand.

## What to take from `ghpkg describe`

- `metadata.name`: upstream's package name. Put it in `provides=` and `conflicts=`.
- `aur_same_app`: the AUR packages that are this same app (their homepage is the repo or upstream's website). Put each in `conflicts=`, and no other AUR names.
- `metadata.description`: becomes `pkgdesc`, with " (from the upstream GitHub release)" after it.
- `metadata.licenses`: becomes `license=`.
- `metadata.depends` and `metadata.optdepends`: already Arch names. They're the starting point for the dependency table (`dependencies.md`), not the final answer.
- `metadata.provides` and `metadata.conflicts`: keep the names (without version constraints) in your own `provides=` and `conflicts=`.
- `unavailable_depends`: upstream's dependencies that the official repos don't have. See `dependencies.md`.
- `scripts`: an `.INSTALL`, if there is one. See below.

## The PKGBUILD

Start from `templates/PKGBUILD.zst` and replace each `@…@` placeholder:

| Placeholder | Value |
|---|---|
| `@PROJECT@` | The project's name, for the comment |
| `@PKGNAME@` | The agreed name, e.g. `myapp-gh` |
| `@GHREPO@` | `owner/repo` |
| `@PKGVER@` | The release tag without a leading `v` |
| `@PKGDESC@` | The description, in double quotes |
| `@LICENSE@`, `@DEPENDS@`, `@OPTDEPENDS@`, `@PROVIDES@`, `@CONFLICTS@` | The items, each in single quotes, separated by spaces |
| `@INSTALL@` | `<pkgname>.install` if an install file was agreed; otherwise delete that line |
| `@FILE@` | The release file name with `$pkgver` in place of the version, in double quotes |
| `@SOURCE@` | `"$url/releases/download/v$pkgver/$_file"`, with the tag written the way `inspect`'s "Download links use the tag" line says: `v$pkgver` or `$pkgver` |
| `@SHA256@` | The sha256 from `describe` |

If the file name has no version in it, set `_file="<pkgname>-$pkgver.pkg.tar.zst"` and write the source as `"$_file::$url/releases/download/v$pkgver/<real file name>"`.

Upstream file names sometimes include their own pkgrel, for example `app-1.2.0-1-x86_64.pkg.tar.zst`. Keep that `-1` as it is: it's part of the file name, not your `pkgrel`.

## Files in /etc

`describe` lists files outside `/usr`. A config file in `/etc` that the user may edit belongs in `backup=`, so an update keeps their copy and saves the new one as `.pacnew`. Propose it and ask, as a layout fix. Theme files and other assets the app only reads don't need it.

## Install scripts

The repack leaves upstream's `.INSTALL` out (it's excluded in `package()`), so
anything it does is lost unless you carry it over:

1. Print the `.INSTALL` and every script it calls in your reply, in full, from `describe`'s `scripts` and `called_scripts`, with a short summary of what each does.
   - Point out any command that pacman's own hooks already run on Arch (the list is in `deb.md`, under "Maintainer scripts"), and propose leaving it out. An `.INSTALL` that does nothing else needs no install file.
2. If they agree, copy its functions into `templates/pkgname.install`, save it as `<pkgname>.install` next to the PKGBUILD, and set `install=<pkgname>.install`.
3. The scripts it calls (such as `/usr/share/<app>/post-install.sh`) ship inside the package, so the install file only needs to call them, as upstream's does.

Example: `omarchy-flux-gh` carries over Flux's three hooks, which run setup scripts in `/usr/share/flux/`.

## Checks before handing over

- `ghpkg test-build <name>` says "the same N files" as the release file. A `.zst` repack should never differ.
- The dependencies are what the user confirmed.
