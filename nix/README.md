# Nix / NixOS

`flake.nix` at the repository root packages the backend (daemon, CLI,
`blueferry-tui`) and the GTK client as one derivation, `packages.blueferry`.
The Qt and Quickshell clients from `packaging/arch/PKGBUILD` are not
packaged here.

## Outputs

- `packages.<system>.blueferry` / `.default` — the package.
- `nixosModules.blueferry` / `.default` — `services.blueferry`.
- `devShells.<system>.default` — a shell with the backend's Python
  dependencies, GTK4/libadwaita, and the lint/test tooling from
  `pyproject.toml`'s `dev` extra.
- `overlays.default` — adds `blueferry` to `pkgs` if you'd rather pull the
  package that way than through `packages.<system>.blueferry`.

Try it without installing anything:

```bash
nix run .#blueferry -- --help
nix run .#blueferry -- doctor
```

## What the NixOS module does

`services.blueferry.enable = true` mirrors the Arch packaging
(`packaging/arch/PKGBUILD`, `systemd/blueferry.service`,
`packaging/arch/blueferry-bluetooth.conf`):

- Adds the package to `environment.systemPackages`, so `blueferry`,
  `blueferry-tui`, and `blueferry-gtk` are on `PATH` and the desktop entry,
  icon, and AppStream metainfo are installed.
- Registers `io.weirdware.BlueFerry.xml` and the session D-Bus service file
  via `services.dbus.packages`, so launching the GTK client D-Bus-activates
  the backend.
- Defines `systemd.user.services.blueferry`, a user-instance unit equivalent
  to the packaged `systemd/blueferry.service`, with the same
  `ConditionPathExists=%h/.config/blueferry/local.env` gate and sandboxing.
- Turns on `hardware.bluetooth.enable` (if not already set) and overrides
  `bluetoothd`'s `ExecStart` to add `--experimental`, since BlueFerry's ANCS
  bearer needs BlueZ's `Bearer.LE1`/`Bearer.BREDR1` interfaces. This
  preserves `hardware.bluetooth.disabledPlugins` if you've set it.
- Enables `security.polkit.enable`, needed by the Polkit-authorized helpers
  in `bluez_setup.py` and `bluetooth_capabilities.py` for first-run pairing.

Override the package with `services.blueferry.package` if you want to patch
or pin it yourself.

## Hardcoded paths patched at build time

BlueFerry's `commands.py` never invokes a shell — every external command is a
fixed argv — but a few of those argv entries are absolute paths sized for
Arch/Debian/Fedora (`/usr/bin/systemctl`, `/usr/bin/btmgmt`,
`/usr/bin/pkexec`) with no `PATH` fallback, so they don't exist on NixOS.
`nix/package.nix`'s `postPatch` rewrites those three to this closure's
`systemd`, `bluez`, and `polkit`. `bluetoothctl`/`obexd` lookups already go
through `shutil.which()`, so those are covered by adding `bluez` to the
wrapped binaries' `PATH` instead.

## Known gaps

- No `checks` output: the test suite wants a private D-Bus session
  (`tests/dbus-test.conf`) plus `ruff`/`mypy`/`bandit`, which
  `packaging/arch/PKGBUILD`'s `check()` runs but this flake doesn't
  replicate. Use `nix develop` and run `pytest` / `ruff` / `mypy` directly.
- Qt and Quickshell clients aren't packaged.
