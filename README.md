# ghpkg

Install apps straight from their GitHub releases as real pacman packages, and keep them updated.

Many projects attach a ready-made `.pkg.tar.zst` or `.deb` to every GitHub release. ghpkg keeps a small PKGBUILD for each app that repackages that file. pacman then tracks every file, removes the app cleanly, and checks dependencies, with no AUR helper and nothing compiled.

- **For Arch Linux and Arch-based systems.** It needs `pacman` and `makepkg`.
- **GitHub releases only,** and prebuilt release files only.
- **x86_64.**

![ghpkg add storytold/pdfcraft, one frame per step: inspecting the release, choosing the name, conflicts and dependencies, saving the PKGBUILD, a test build, then installing with pacman](docs/ghpkg-add.gif)

## Install

```bash
git clone https://github.com/kshatriya-abhay/ghpkg
cd ghpkg
./install.sh
```

`install.sh` installs ghpkg from its latest GitHub release **as a ghpkg package**, `ghpkg-gh`, so `ghpkg update` keeps ghpkg itself updated too. On Omarchy it also offers to add the post-update hook (below). It asks for sudo once, to install.

ghpkg needs `bash`, `curl`, `jq`, `base-devel` (for `makepkg` and `fakeroot`), `pacman-contrib` (for `updpkgsums`), `libarchive` (for `bsdtar`) and `binutils` (for `readelf`).

**Log in to GitHub for higher limits.** Without a login, GitHub allows 60 API requests an hour, which a handful of packages can use up. With `gh auth login` (from `github-cli`), or a `GITHUB_TOKEN` environment variable, ghpkg uses your token and gets 5000 an hour. ghpkg prints a tip when it has no token; `GHPKG_NO_TIPS=1` turns tips off. (The token doesn't change download speeds: release files come from GitHub's file servers either way.)

To install from the checkout without pacman tracking it, `make install` copies ghpkg into `~/.local` (or `sudo make install PREFIX=/usr`).

## Commands

| Command | What it does |
|---|---|
| `ghpkg check-update` | Lists every package and whether it can be updated, then a summary line. Changes nothing. |
| `ghpkg update [package...]` | For each package with a newer release: sets the PKGBUILD's version, takes the checksum from GitHub, then builds and installs with `makepkg -si`. With no names it updates every installed package. Name a package that isn't installed yet to install it. |
| `ghpkg list` | Lists the packages with their installed and PKGBUILD versions and GitHub repos. Works offline. |
| `ghpkg remove <package>` | Uninstalls a package, then asks whether to delete its PKGBUILD folder too. |
| `ghpkg add <owner/repo>` | Adds an app whose release has a `.pkg.tar.zst`, asking you at each step (below). |
| `ghpkg inspect <owner/repo>` | Shows the latest release's Linux x86_64 files, best first, whether the official repos have the app, and which names are taken on the AUR. |
| `ghpkg describe <owner/repo> <file>` | Downloads a `.pkg.tar.zst` or `.deb` from the release, checks it against GitHub's checksum, and shows what's inside: dependencies, scripts that run as root, files, linked libraries, the AUR packages that are this same app, and what needs a decision, such as dependencies the official repos don't have. Runs nothing from the package. |
| `ghpkg test-build <package>` | Builds a package without installing it, compares its files and their permissions with the release file, and checks that its download links are files of the latest release. |
| `ghpkg skill install` | Links the ghpkg skill into your coding agents' skill folders (below). |
| `ghpkg hook install [--update]` | On Omarchy, runs ghpkg after every `omarchy update` (below). |
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

## Adding an app

### From a `.pkg.tar.zst`: `ghpkg add`

Many projects attach a ready-made Arch package to their releases. `ghpkg add` turns one into a ghpkg package, asking you at each step. Nothing is written until you say so:

1. **The release:** which file to use, and a warning if the official repos already have the app.
2. **What's inside:** the package's metadata, dependencies and files, and any script it runs as root, shown in full.
3. **The name:** `<app>-gh` by default, checked against the AUR. If the AUR has the same app under other names (matched by its homepage), you choose which ones yours replaces. An unrelated package that only shares a name is never added.
4. **Dependencies:** upstream's list, plus packages that own the libraries the programs link to. Each says where it came from and whether it's installed. Keep them, take upstream's only, or edit the list.
5. **Scripts that run as root:** carry upstream's install script over, leave it out, or stop.
6. **The PKGBUILD:** shown in full before it's saved.
7. **A test build,** then an offer to install.

```bash
ghpkg add storytold/pdfcraft
```

### From a `.deb`: with a coding agent

Packaging a `.deb` takes judgement: Debian's dependency names need translating, maintainer scripts don't map onto pacman's, and the files often need moving. ghpkg comes with an agent skill for this:

```bash
ghpkg skill install      # links it into ~/.claude/skills, ~/.codex/skills and ~/.agents/skills
```

Then ask your agent to add the app with ghpkg. The skill has it use `inspect`, `describe` and `test-build` for the mechanical work. It stops to ask you about:
- the release file and name
- the dependencies, from a table that says where each came from
- every script that runs as root
- each layout fix
- the final PKGBUILD

It never installs anything: it hands you the `ghpkg update` command to run yourself. The same skill helps with `.zst` releases, and with fixing an update that fails.

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

On [Omarchy](https://omarchy.org), ghpkg can run at the end of every `omarchy update`:

```bash
ghpkg hook install            # list the packages that can be updated; never installs
ghpkg hook install --update   # install the updates too; pacman still asks first
ghpkg hook status             # which one is installed
ghpkg hook remove
```

`install.sh` offers the first one.

## Roadmap

Done in 1.0:
- the standalone tool and its tests
- the agent skill, with `inspect`, `describe` and `test-build`
- `ghpkg add` for `.pkg.tar.zst` releases
- ghpkg installing itself as a ghpkg package
- the Omarchy hook command

Next:

- **Safer updates.**
  - When upstream renames its release file, `ghpkg update` offers the closest match instead of failing.
  - Before installing an update, it shows what changed in the dependencies and in any script that runs as root, and asks.
- **Later, maybe.**
  - `ghpkg add` for `.deb` releases with no agent.
  - `.tar.gz` and AppImage releases.
  - Checking release signatures where upstream signs them.
  - Update notices on systems without Omarchy.
  - aarch64.

## Development

```bash
sudo pacman -S bats shellcheck
make lint test
make install-dev     # link ~/.local/bin/ghpkg to this checkout
```

Releases: set the version in `lib/common.sh` and `packaging/PKGBUILD`, commit, and push a tag such as `v1.0.1`. GitHub Actions tests it, builds the package and publishes the release.

The tests replace `curl`, `gh`, `sudo`, `pacman` and `makepkg` with stand-ins from `test/stubs`, so they never touch the network, sudo or your packages.

## License

MIT
