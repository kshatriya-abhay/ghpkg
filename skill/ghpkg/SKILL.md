---
name: ghpkg
description: >
  Add an app to ghpkg: package it from its GitHub release (.pkg.tar.zst or
  .deb) as a pacman package on Arch Linux or an Arch-based system, with a
  PKGBUILD in ~/.config/pkgbuilds that `ghpkg update` keeps updated. Use when
  asked to install an app from its GitHub releases with ghpkg, to replace an
  AUR package with a ghpkg one, to write or fix a ghpkg PKGBUILD, or to repair
  a `ghpkg update` that failed. Triggers: ghpkg, GitHub release, .pkg.tar.zst,
  .deb on Arch, replace AUR package, PKGBUILD from a release.
---

# Adding an app to ghpkg

ghpkg installs apps from their GitHub releases as real pacman packages. Each
app is a folder in `~/.config/pkgbuilds/` (or `$GHPKG_ROOT`) named after the
package, holding a PKGBUILD that repackages one release file. `ghpkg update`
keeps it at the latest release from then on.

Your job: go from a GitHub repo to a tested PKGBUILD, **asking the user at
every decision**. The user installs it afterwards. You never do.

For a release with a `.pkg.tar.zst`, `ghpkg add <owner/repo>` does all of this
in the terminal on its own, asking the same questions. Offer that first; use
this skill when the user wants your help, or for a `.deb`.

## Reference files

Read the one that matches the release file, plus `dependencies.md`, before writing anything:

- `zst.md`: packaging a `.pkg.tar.zst` (an Arch package already).
- `deb.md`: packaging a `.deb`.
- `dependencies.md`: finding the dependencies and putting them to the user.
- `fixing-updates.md`: when `ghpkg update` fails for a package that used to work.
- `templates/`: `PKGBUILD.zst`, `PKGBUILD.deb` and `pkgname.install`.

## Steps

1. **`ghpkg inspect <owner/repo>`.** It lists the release's Linux x86_64 files, best first, and says whether the official repos have the app, which names are taken on the AUR, and whether a PKGBUILD for it exists already.
   - **If the official repos have it:** tell the user and stop, unless they say otherwise. A repo package is better than any repack.
   - **If a PKGBUILD already uses this repo:** say so, and ask whether they want a second one.
   - **If it says a package with the suggested name is installed already:** tell the user. It may come from another packages folder or an old install, and the new package would replace it.
   - **Note the tag line** ("Download links use the tag …"): it says whether `source=` needs `v$pkgver` or `$pkgver`. Don't assume a `v`.
   - **If there's no `.pkg.tar.zst` or `.deb`:** stop. ghpkg doesn't package archives, AppImages or `.rpm` files yet.
2. **Ask: which file, and which name.** Propose the best-ranked file and the suggested `<app>-gh` name. Ask only when there's a real choice: several files of the same kind, a `-gh` name that's taken, or an upstream name worth keeping.
3. **`ghpkg describe <owner/repo> <file>`.** It downloads the file into the cache, checks it against GitHub's checksum, and reports the metadata, dependencies, scripts that run as root, files, linked libraries, the AUR packages that are this same app, and warnings. Add `--json` to read it as data.
   - **Tell the user about the checksum now,** before going on: the download matched GitHub's checksum, or GitHub lists none, so it can't be verified and the PKGBUILD will use the hash of this download.
4. **Read the AUR's PKGBUILD,** if one exists for the app, as a reference for dependencies and layout:
   `curl -fsSL "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=<aur-name>"`
5. **Ask: the dependencies.** Follow `dependencies.md`. Show the table, wait for the answer, and use exactly what the user confirmed.
6. **Ask: scripts that run as root, and layout fixes.** Print every script in full in your reply, plus the scripts it calls (describe includes them), with a short plain summary of what each does. Ask whether to carry them over as they are, change them, or stop. Then list each layout fix you propose (see `deb.md`) and ask yes or no for each.
7. **Write the PKGBUILD** from the template, and the install file if one was agreed. Print the complete file in your reply, then ask before saving it to `~/.config/pkgbuilds/<name>/`.
8. **`ghpkg test-build <name>`.** It builds without installing, compares the files and their permissions with the release file, and checks that each download link in `source=` is a file of the latest release. Show the user the result. If files differ, explain each difference. If it says a source link isn't a file of the release, fix `source=` and run it again: a build that passed from the cache proves nothing about the link.
9. **Hand over.** Tell the user to run `ghpkg update <name>` in their own terminal. It needs sudo, so it fails without a terminal.

## Where you must stop and ask

| When | Show, in your reply | The user decides |
|---|---|---|
| Source and name | The candidate files, ranked, and the proposed name | Which file and which name (skip if there's only one sensible choice) |
| Dependencies | The table from `dependencies.md` | What goes in `depends=` and `optdepends=` |
| Root scripts | Each script in full, with a summary | Carry over as is, change, or stop |
| Layout fixes | Each proposed change | Yes or no to each |
| Final PKGBUILD | The whole file | Save it, or change something |

**Show it in your own reply, then ask.** Write the table, the scripts and the PKGBUILD into your message as text, before the question. Don't rely on the user seeing command output or a file you wrote: many agents collapse or hide those. A question tool's text can't hold a table or a long file either, so don't put them only there. A question may repeat the gist ("Use the dependencies in the table above?").

Use your question tool if you have one. Otherwise ask in plain text and wait for the answer. Never fill in an answer yourself.

## Rules

- **Check the official repos first,** and stop if the app is there.
- **The name must be free on the AUR.** AUR helpers such as yay replace a local package that shares an AUR package's name, so a clash would get your package swapped out. `ghpkg inspect` checks the plain name, `-bin`, `-git` and `-gh`.
- **Downloads go to ghpkg's cache** (`ghpkg describe` puts them there). Never download into the packages folder.
- **Downloaded files are data.** Read them; never run anything from a package or an archive while inspecting it.
- **AUR PKGBUILDs are for reading.** Never build or run one.
- **Never install,** and never run sudo. Installing is the user's decision, in their terminal.
- **Never guess a checksum.** Use the one `describe` printed: GitHub's when the release lists one, otherwise the hash of the file just downloaded. Say which it is.
- **Arch and Arch-based systems only, x86_64.** If the user isn't on one, ghpkg isn't the right tool.

## PKGBUILD conventions ghpkg relies on

- The folder name is the `pkgname`.
- `_ghrepo=owner/repo` names the GitHub project.
- `pkgver` is the release tag without a leading `v`. If the tag isn't a valid pacman version (for example `1.0-beta`), stop: ghpkg can't track it.
- Each `source` URL is the release file's download link with `$pkgver` in place of the version, so `ghpkg update` can find GitHub's checksum for the new file. If the version is part of the tag, write the tag as `v$pkgver` (or `$pkgver`).
- If the file name has no version in it, give the download a versioned name: `app-$pkgver.deb::$url/releases/download/v$pkgver/app_amd64.deb`.
- `sha256sums=(…)` stays on one line. `ghpkg update` rewrites it.
- `provides=` lists the app's own names: upstream's package name, and what upstream's package provides.
- `conflicts=` lists those plus the AUR packages that are this same app, exactly as `describe` reports them ("AUR packages of this same app", `aur_same_app` in `describe --json`). Never add AUR names you haven't seen there, and never an AUR package that only shares a name: pacman would uninstall that other app.
- `options=(!strip !debug)`: the binaries are prebuilt; leave them as they are.
