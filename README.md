# ghpkg

Install apps straight from their GitHub releases as real pacman packages, and keep them updated.

Many projects attach a ready-made `.pkg.tar.zst` or `.deb` to every GitHub release. ghpkg keeps a small PKGBUILD for each app that repackages that file. pacman then tracks every file, removes the app cleanly, and checks dependencies, with no AUR helper and nothing compiled.

- **For Arch Linux and Arch-based systems.** It needs `pacman` and `makepkg`.
- **GitHub releases only,** and prebuilt release files only.
- **x86_64.**

## Install

```bash
git clone https://github.com/kshatriya-abhay/ghpkg
cd ghpkg
make install            # into ~/.local; or: sudo make install PREFIX=/usr
```

`packaging/PKGBUILD` builds ghpkg itself as a pacman package from a tagged release.

ghpkg needs `bash`, `curl`, `jq`, `pacman`, `pacman-contrib` (for `updpkgsums`), `libarchive` (for `bsdtar`) and `sudo`. `github-cli` is optional: when you're logged in with `gh`, ghpkg uses your token, so GitHub allows 5000 requests an hour instead of 60. A `GITHUB_TOKEN` environment variable works too.

## Commands

| Command | What it does |
|---|---|
| `ghpkg check-update` | Lists every package and whether it can be updated, then a summary line. Changes nothing. |
| `ghpkg update [package...]` | For each package with a newer release: sets the PKGBUILD's version, takes the checksum from GitHub, then builds and installs with `makepkg -si`. With no names it updates every installed package. Name a package that isn't installed yet to install it. |
| `ghpkg list` | Lists the packages with their installed and PKGBUILD versions and GitHub repos. Works offline. |
| `ghpkg remove <package>` | Uninstalls a package, then asks whether to delete its PKGBUILD folder too. |
| `ghpkg help [command]` | Shows help. |

`update` and `remove` need a terminal, because sudo asks for your password. Without one, ghpkg stops before downloading or changing anything.

```
$ ghpkg check-update
nbfc-linux-gh 0.5.4-1 (up to date)
photocraft-gh 0.23.0-1 -> 0.23.1
stremio-service-gh 0.1.22-1 (up to date)
ghpkg: 1 packages can be updated. 2/3 packages up-to-date.
run `ghpkg update`
```

## Where things live

- **PKGBUILDs:** `~/.config/pkgbuilds/<package>/PKGBUILD`, one folder per package. Set `GHPKG_ROOT` to use another folder. Keeping it in your dotfiles works well.
- **Downloads and builds:** `~/.cache/ghpkg`, or `GHPKG_CACHE`. The PKGBUILD folders never get build files in them. After an update, the cache keeps the new package and the one it replaced, so you can go back with `sudo pacman -U ~/.cache/ghpkg/packages/<package>-<old version>-*.pkg.tar.zst`.

## Writing a PKGBUILD for ghpkg

A ghpkg PKGBUILD is an ordinary PKGBUILD that follows a few conventions:

- **The folder name is the `pkgname`.**
- **`_ghrepo=owner/repo`** names the GitHub project whose releases ghpkg checks.
- **`pkgver` is the release tag without a leading `v`.** Tags that aren't valid pacman versions (such as `1.0-beta`) are refused. Pre-releases are never picked up.
- **Each `source` URL is the release file's download link, with `$pkgver` in place of the version.** ghpkg finds GitHub's checksum for a file by matching that link.
- **If the release file's name has no version in it, give it one:** `myapp-$pkgver.deb::$url/releases/download/v$pkgver/myapp_amd64.deb`. Otherwise every version would download to the same file name.
- **Keep `sha256sums=(…)` on one line.** ghpkg rewrites that line.
- **Name it `<app>-gh`, and check that the AUR doesn't have that name.** AUR helpers such as yay replace a local package that shares an AUR package's name.
- **`provides=` and `conflicts=`** should list the app's other package names (upstream's own, the AUR's), so installing yours replaces them cleanly.

A PKGBUILD that repackages a release's `.pkg.tar.zst`:

```bash
pkgname=myapp-gh
_ghrepo=someone/myapp
pkgver=1.4.0
pkgrel=1
pkgdesc="My app (from the upstream GitHub release)"
arch=(x86_64)
url="https://github.com/$_ghrepo"
license=(MIT)
depends=(gtk3)
provides=(myapp)
conflicts=(myapp myapp-bin)
options=(!strip !debug)
_file=myapp-$pkgver-x86_64.pkg.tar.zst
source=("$url/releases/download/v$pkgver/$_file")
noextract=("$_file")
sha256sums=('…')

package() {
  bsdtar -xf "$srcdir/$_file" -C "$pkgdir" \
    --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL
}
```

If upstream's package has an install script (`.INSTALL`), copy what it does into an `install=` file of your own: the repack leaves the original out.

## Omarchy

On [Omarchy](https://omarchy.org), a post-update hook lists your ghpkg packages at the end of every `omarchy update`. It only reports, and never installs:

```bash
omarchy hook install post-update integrations/omarchy/ghpkg-check-update.hook
```

## Development

```bash
sudo pacman -S bats shellcheck
make lint test
make install-dev     # link ~/.local/bin/ghpkg to this checkout
```

The tests replace `curl`, `gh`, `sudo`, `pacman` and `makepkg` with stand-ins from `test/stubs`, so they never touch the network, sudo or your packages.

## License

MIT
