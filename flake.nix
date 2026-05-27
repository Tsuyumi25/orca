{
  description = "Orca personal fork — dev shell with Electron runtime libs for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Why: electron 41's prebuilt ELF dlopen()s these libs by SONAME at
        # runtime; NixOS has no FHS so we expose them via LD_LIBRARY_PATH.
        # Keep in sync with the buildInputs in
        # nix-config/overlays/orca-ai.nix — the .deb-repack derivation on the
        # consumer side needs the same set, divergence would silently break
        # one path or the other.
        electronRuntimeLibs = with pkgs; [
          alsa-lib
          atk
          at-spi2-atk
          at-spi2-core
          cairo
          cups
          dbus
          expat
          glib
          gtk3
          libdrm
          libGL
          libgbm
          libnotify
          libsecret
          libuuid
          libxkbcommon
          mesa
          nspr
          nss
          pango
          stdenv.cc.cc.lib
          udev
          libx11
          libxcb
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxrandr
          libxscrnsaver
          libxtst
        ];

        # Why: node-gyp builds for better-sqlite3, node-pty, cpu-features need
        # a C/C++ toolchain and Python 3 at install time. node 24 to match
        # package.json engines.
        buildDeps = with pkgs; [
          nodejs_24
          pnpm
          gcc
          gnumake
          python3
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          name = "orca-dev";
          nativeBuildInputs = buildDeps ++ electronRuntimeLibs;
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath electronRuntimeLibs;

          # Why: `nix develop` sets SHELL to the dev bash it provides. Orca's
          # PTY picks the terminal shell from $SHELL, so `pnpm dev` launched
          # from here inherits SHELL=bash and opens a bash terminal without the
          # user's zsh config (aliases, zoxide, prompt) instead of their real
          # login shell. Point SHELL back at zsh so orca-dev matches the
          # GUI-launched app, which inherits the login session's zsh.
          shellHook = ''
            export SHELL="${pkgs.zsh}/bin/zsh"
          '';
        };
      }
    );
}
