{
  lib,
  python3Packages,
  bluez,
  systemd,
  gtk4,
  libadwaita,
  libsecret,
  gobject-introspection,
  wrapGAppsHook4,
}:

let
  pyproject = lib.importTOML ../pyproject.toml;
in
python3Packages.buildPythonApplication {
  pname = "blueferry";
  version = pyproject.project.version;
  pyproject = true;

  src = ../.;

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  dependencies = with python3Packages; [
    cryptography
    textual
    typer
    # Native desktop bindings that upstream deliberately leaves out of
    # pyproject.toml's dependencies (see the comment there) because
    # distributions are expected to supply them; nixpkgs supplies them here.
    dbus-python
    pygobject3
  ];

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    libsecret
  ];

  # BlueFerry never invokes a shell (src/blueferry/commands.py), so every
  # helper it runs is a fixed argv. A handful of entries are hardcoded
  # absolute paths with no PATH fallback, sized for Arch/Debian/Fedora, and
  # simply don't exist on NixOS. Point them at this closure's copies instead
  # of patching upstream. bluetoothctl/obexd lookups already go through
  # shutil.which, so those are covered by the PATH prefix added below rather
  # than by substitution.
  #
  # pkexec is the one exception: it refuses to run unless it's the setuid
  # root binary, and Nix store paths are never setuid (the store is shared,
  # read-only, and multi-user). NixOS instead publishes a setuid copy at the
  # fixed path /run/wrappers/bin/pkexec via security.wrappers, which
  # services.blueferry's NixOS module enables through security.polkit.enable.
  # That path is a NixOS convention, not something in this closure, so it's
  # a literal rather than a package reference.
  postPatch = ''
    substituteInPlace src/blueferry/bluez_setup.py \
      --replace-fail '"/usr/bin/btmgmt"' '"${bluez}/bin/btmgmt"' \
      --replace-fail 'pkexec = "/usr/bin/pkexec"' 'pkexec = "/run/wrappers/bin/pkexec"'

    substituteInPlace src/blueferry/bluetooth_capabilities.py \
      --replace-fail '"/usr/bin/btmgmt"' '"${bluez}/bin/btmgmt"' \
      --replace-fail '"/usr/bin/systemctl"' '"${systemd}/bin/systemctl"' \
      --replace-fail 'Path("/usr/bin/pkexec")' 'Path("/run/wrappers/bin/pkexec")'

    substituteInPlace src/blueferry/backend_lifecycle.py \
      --replace-fail '"/usr/bin/systemctl"' '"${systemd}/bin/systemctl"'

    substituteInPlace src/blueferry/pair_setup.py \
      --replace-fail '"/usr/bin/systemctl"' '"${systemd}/bin/systemctl"'
  '';

  # The test suite wants a private D-Bus session (tests/dbus-test.conf) plus
  # lint/type-check tooling; replicating packaging/arch/PKGBUILD's check()
  # here is more than a Nix packaging pass needs. Run `pytest` from a
  # `nix develop` shell instead.
  doCheck = false;

  # bluetoothctl/obexd are looked up with shutil.which(), so they need to be
  # on PATH; everything else that mattered was patched above instead.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ bluez ]}
    )
  '';

  postInstall = ''
    install -Dm644 data/icons/io.weirdware.BlueFerry.Gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/io.weirdware.BlueFerry.Gtk.svg"
    install -Dm644 data/io.weirdware.BlueFerry.Gtk.desktop \
      "$out/share/applications/io.weirdware.BlueFerry.Gtk.desktop"
    install -Dm644 data/io.weirdware.BlueFerry.Gtk.metainfo.xml \
      "$out/share/metainfo/io.weirdware.BlueFerry.Gtk.metainfo.xml"
    install -Dm644 data/io.weirdware.BlueFerry.xml \
      "$out/share/dbus-1/interfaces/io.weirdware.BlueFerry.xml"

    install -Dm644 packaging/arch/io.weirdware.BlueFerry.service \
      "$out/share/dbus-1/services/io.weirdware.BlueFerry.service"
    substituteInPlace "$out/share/dbus-1/services/io.weirdware.BlueFerry.service" \
      --replace-fail "/usr/bin/blueferry" "$out/bin/blueferry"
  '';

  meta = {
    description = "iPhone messages, notifications, and contacts on Linux over Bluetooth (backend + GTK client)";
    homepage = "https://github.com/erikwb/blueferry";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "blueferry";
  };
}
