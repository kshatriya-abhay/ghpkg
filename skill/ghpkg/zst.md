# Packaging a .pkg.tar.zst

The release file is already an Arch package. The PKGBUILD only unpacks it into
`$pkgdir` under a new name, so pacman and ghpkg can manage it.
`ghpkg add <owner/repo>` does all of this on its own; this is for doing it
with the user by hand.

## What to take from `ghpkg describe`

- `metadata.name`: upstream's package name. Put it in `provides=` and `conflicts=`.
- `metadata.description`: becomes `pkgdesc`, with " (from the upstream GitHub release)" after it.
- `metadata.licenses`: becomes `license=`.
- `metadata.depends` and `metadata.optdepends`: already Arch names. They're the starting point for the dependency table (`dependencies.md`), not the final answer.
- `metadata.provides` and `metadata.conflicts`: keep the names (without version constraints) in your own `provides=` and `conflicts=`.
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
| `@SOURCE@` | `"$url/releases/download/v$pkgver/$_file"` (drop the `v` if the tag has none) |
| `@SHA256@` | The sha256 from `describe` |

If the file name has no version in it, set `_file="<pkgname>-$pkgver.pkg.tar.zst"` and write the source as `"$_file::$url/releases/download/v$pkgver/<real file name>"`.

Upstream file names sometimes include their own pkgrel, for example `app-1.2.0-1-x86_64.pkg.tar.zst`. Keep that `-1` as it is: it's part of the file name, not your `pkgrel`.

## Install scripts

The repack leaves upstream's `.INSTALL` out (it's excluded in `package()`), so
anything it does is lost unless you carry it over:

1. Show the user the `.INSTALL` and every script it calls, from `describe`'s `scripts` and `called_scripts`, with a short summary of what each does.
2. If they agree, copy its functions into `templates/pkgname.install`, save it as `<pkgname>.install` next to the PKGBUILD, and set `install=<pkgname>.install`.
3. The scripts it calls (such as `/usr/share/<app>/post-install.sh`) ship inside the package, so the install file only needs to call them, as upstream's does.

Example: `omarchy-flux-gh` carries over Flux's three hooks, which run setup scripts in `/usr/share/flux/`.

## Checks before handing over

- `ghpkg test-build <name>` says "the same N files" as the release file. A `.zst` repack should never differ.
- The dependencies are what the user confirmed.
