# Fixing a failed `ghpkg update`

When `ghpkg update` fails for a package that used to work, it says which
package failed. If it had already moved the PKGBUILD to the new version, it
says that too, and leaves it there.

## Find out what changed

1. **Run `ghpkg inspect <owner/repo>`** and compare the release's files with the PKGBUILD's `source=` line. The usual cause is a renamed file. For example, R Quick Share's file name includes a glibc version (`r-quick-share-main_v0.11.5_glibc-2.39_amd64.deb`), which will change some day.
2. **Run `ghpkg test-build <pkg>`** to see makepkg's own error without installing anything.

## Common fixes

| Problem | Fix |
|---|---|
| The release file was renamed | Update the file name in `source=` (or `_file=`) to the new pattern, keeping `$pkgver` in place of the version. Show the user the change |
| The checksum doesn't match | Don't paste a new one. Ask the user: it may mean the file changed after release. `ghpkg update` takes the checksum from GitHub again on the next try |
| The tag isn't a valid version | ghpkg can't track a tag like `1.0-beta`. Tell the user; wait for the next proper release |
| A new dependency is missing | Run `ghpkg describe` on the new file and compare its dependencies with the PKGBUILD's. Go through `dependencies.md` with the user for the new ones |
| The install script changed | Show the user the old and the new script, side by side, before changing the install file |

After a fix, run `ghpkg test-build <pkg>` again, then tell the user to run
`ghpkg update <pkg>` in their terminal.

## Going back

The cache keeps the package that was replaced:

```
sudo pacman -U ~/.cache/ghpkg/packages/<pkg>-<old version>-*.pkg.tar.zst
```

The user runs that. Then leave the package out of `ghpkg update` until upstream fixes the release.
