{
  description = "Orca personal fork — dev shell + electron app package for NixOS";

  inputs = {
    # Why: pin to the same release branch the typical consumer's NixOS is on
    # so glibc / electron-runtime libs match at runtime. Consumers on a
    # different channel should override via inputs.orca.inputs.nixpkgs.follows.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    # Why: overlays.default is a top-level (non-per-system) output — it
    # tells consuming nixpkgs how to expose orca-ai under its usual attr name.
    # The per-system outputs (devShells/packages) are merged in via the
    # flake-utils helper below.
    {
      overlays.default = final: prev: {
        orca-ai = self.packages.${final.system}.default;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        # Why: electron 41's prebuilt ELF dlopen()s these libs by SONAME at
        # runtime; NixOS has no FHS so we expose them via LD_LIBRARY_PATH (dev
        # shell) or autoPatchelf + buildInputs (package). Keep in sync with
        # the buildInputs in nix-config/overlays/orca-ai.nix.
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
          # Why: electron-builder's bundled chrome binary links libpulse/FLAC
          # (audio), libxslt (XML). These weren't needed by the prebuilt .deb
          # path because the .deb's electron was already linked against an
          # older audio stack. nixpkgs electron resolves these at autoPatchelf
          # time, so we have to provide them.
          libpulseaudio
          flac
          libxslt
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

        version = (lib.importJSON ./package.json).version;
      in
      {
        devShells.default = pkgs.mkShell {
          name = "orca-dev";
          nativeBuildInputs = buildDeps ++ electronRuntimeLibs;
          LD_LIBRARY_PATH = lib.makeLibraryPath electronRuntimeLibs;

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

        packages.default = pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "orca-ai";
          inherit version;

          # Why: lib.cleanSourceWith filters out files that shouldn't enter the
          # nix store. HANDOFF.md is local-only and not git-tracked (per
          # .git/info/exclude in the fork); node_modules/out/dist are build
          # artifacts that would invalidate the FOD if present.
          src = lib.cleanSourceWith {
            src = ./.;
            filter =
              path: type:
              let
                base = baseNameOf (toString path);
              in
              !(lib.elem base [
                ".git"
                "node_modules"
                "out"
                "dist"
                "HANDOFF.md"
              ])
              # Why: electron-vite's dev mode drops stale config copies named
              # electron.vite.config.<timestamp>.mjs into the repo root. Filter
              # those without catching the real electron.vite.config.ts.
              && (builtins.match "electron\\.vite\\.config\\.[0-9]+\\.mjs" base == null);
          };

          # Why: pnpm.fetchDeps populates an offline store from pnpm-lock.yaml;
          # pnpm.configHook then runs `pnpm install --offline` against it in
          # buildPhase. First-time hash is found by setting lib.fakeHash and
          # reading the "got: ..." line from the nix build error.
          # Why: orca's pnpm-lock.yaml + patchedDependencies are written by
          # pnpm 10 (per packageManager pin). nixpkgs' top-level `pnpm` is
          # currently 11.x, which validates patchedDependencies differently
          # and rejects the lockfile as out-of-sync. Pin pnpm_10.
          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (finalAttrs) pname version src;
            pnpm = pkgs.pnpm_10;
            fetcherVersion = 1;
            hash = "sha256-2GNtqJvhcpy36rzt5Z7V9O/bPafbyFZA7jKaVnDgzI4=";
          };

          nativeBuildInputs = with pkgs; [
            nodejs_24
            pnpm_10
            pnpmConfigHook
            python3
            makeWrapper
            autoPatchelfHook
            copyDesktopItems
          ];

          buildInputs = electronRuntimeLibs;

          # Why: orca's npm postinstall calls config/scripts/rebuild-native-deps.mjs
          # which tries to ensure electron's prebuilt binary is on disk. We skip
          # that download and use nixpkgs electron at runtime via makeWrapper.
          # Native modules (better-sqlite3, node-pty, cpu-features) still get
          # rebuilt against electron's ABI via @electron/rebuild — pkgs.electron
          # provides the headers it needs through ELECTRON_OVERRIDE_DIST_PATH.
          env = {
            ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
            # Why: electron-builder auto-detects macOS code signing certs and
            # fails if none found. We're on Linux but the config has macOS
            # entries — disable detection so the linux-dir target doesn't
            # tangentially trip on cert lookup.
            CSC_IDENTITY_AUTO_DISCOVERY = "false";
            # Why: native modules (better-sqlite3, node-pty, cpu-features)
            # compile with node-gyp, which by default downloads node headers
            # from nodejs.org. The sandbox has no network — point at nixpkgs
            # electron's headers so gyp finds them locally AND compiles
            # against electron's ABI (electron's bundled V8 differs from
            # upstream node's). Same `--nodedir=${electron.headers}` pattern
            # used by anytype and other nixpkgs electron apps.
            npm_config_nodedir = "${pkgs.electron.headers}";
            # Why: package.json's `packageManager: pnpm@10.24.0+...` triggers
            # pnpm 10's auto-install of that exact version from the registry.
            # The nix sandbox has no network — disable the enforcement and
            # use whatever pnpm we provided in nativeBuildInputs (pnpm_10).
            pnpm_config_manage_package_manager_versions = "false";
            # Telemetry stays disabled — these envs are only set by upstream
            # CI release jobs (see electron.vite.config.ts). Default = null.
          };

          buildPhase = ''
            runHook preBuild

            # Why: `packageManager: pnpm@10.24.0+...` triggers pnpm's auto-
            # install of that exact version from the registry on every
            # invocation. Strip it so pnpm uses our pnpm_10 from PATH.
            ${pkgs.jq}/bin/jq 'del(.packageManager)' package.json > package.json.tmp \
              && mv package.json.tmp package.json

            # Why: provide nixpkgs electron to electron-builder via a writable
            # copy. electron-builder's --dir target expects a "dist" directory
            # to copy the electron runtime from — by default it'd download
            # from the internet, which the sandbox can't do. teams-for-linux
            # uses the same trick.
            cp -r ${pkgs.electron.dist} electron-dist
            chmod -R u+w electron-dist

            # Why: rebuild native modules against electron's ABI. We do this
            # ourselves (rather than letting electron-builder's npmRebuild
            # call it) because electron-builder runs `npm rebuild` which is
            # confused by pnpm's .pnpm/ store layout. After this our compiled
            # .node bindings are in place; electron-builder will pick them up.
            HOME=$TMPDIR pnpm rebuild --reporter=append-only

            # Build app code: main + preload + renderer (electron-vite),
            # plus the relay daemon bundles and CLI. Skip build:computer-macos
            # (mac only) and build:web (separate web-only deployment target).
            HOME=$TMPDIR pnpm run build:relay
            HOME=$TMPDIR pnpm run build:cli
            HOME=$TMPDIR pnpm run build:electron-vite

            # Why: electron-builder --dir produces dist/linux-unpacked/ with
            # the app properly packaged (asar + asar.unpacked + extraResources
            # at the layout the runtime expects), but skips the .deb/AppImage
            # packaging step (which needs fakeroot/dpkg and adds nothing once
            # nix has its own packaging). -c.electronDist points it at our
            # nixpkgs electron so it doesn't try to download. -c.npmRebuild=false
            # skips the npm-rebuild step we already did manually above.
            HOME=$TMPDIR ./node_modules/.bin/electron-builder \
              --config config/electron-builder.config.cjs \
              --dir \
              -c.electronDist="$PWD/electron-dist" \
              -c.electronVersion=${pkgs.electron.version} \
              -c.npmRebuild=false

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/lib/orca-ai $out/bin

            # Why: dist/linux-unpacked has everything in the layout that the
            # runtime expects (orca-ide as the electron entry, resources/
            # with app.asar + app.asar.unpacked + extraResources). Wholesale
            # copy preserves that, same as ~/nix-config/overlays/orca-ai.nix
            # does after dpkg-deb -x of the upstream .deb.
            cp -r dist/linux-unpacked/. $out/lib/orca-ai/

            # Why: drop electron-builder's auto-update channel manifest —
            # there's no upstream release feed at the .deb's expected URL
            # for our fork, and the auto-updater would noise the console.
            rm -f $out/lib/orca-ai/resources/app-update.yml

            # Why: makeWrapper points at orca-ide (the nixpkgs electron
            # copy renamed by electron-builder). --no-sandbox skips the
            # SUID chrome-sandbox helper (which can't have its SUID bit set
            # inside /nix/store — system-level NixOS chromium sandbox would
            # need security.chromiumSuidSandbox.enable=true elsewhere).
            # Electron still uses its namespace sandbox fallback. ozone hint
            # + Wayland flags mirror the upstream .deb wrapper.
            makeWrapper $out/lib/orca-ai/orca-ide $out/bin/orca-ai \
              --add-flags "--no-sandbox" \
              --add-flags "--ozone-platform-hint=auto" \
              --add-flags "--enable-features=WaylandWindowDecorations" \
              --add-flags "--enable-wayland-ime=true" \
              --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath electronRuntimeLibs}" \
              --prefix PATH : "${lib.makeBinPath [ pkgs.xdg-utils ]}"

            # Why: the orca CLI shipped under resources/bin/orca is a node
            # script. electron-builder copies it from resources/linux/bin/orca
            # without preserving the executable bit. chmod + patchShebangs
            # turn it into a runnable file before makeWrapper exposes it.
            if [ -f "$out/lib/orca-ai/resources/bin/orca" ]; then
              chmod +x "$out/lib/orca-ai/resources/bin/orca"
              patchShebangs "$out/lib/orca-ai/resources/bin"
              makeWrapper "$out/lib/orca-ai/resources/bin/orca" $out/bin/orca-ai-cli
            fi

            install -Dm644 resources/icon.png \
              $out/share/icons/hicolor/256x256/apps/orca-ide.png

            runHook postInstall
          '';

          desktopItems = [
            (pkgs.makeDesktopItem {
              name = "orca-ai";
              exec = "orca-ai %U";
              icon = "orca-ide";
              desktopName = "Orca";
              genericName = "AI agent IDE";
              comment = "Next-gen IDE for parallel agentic development";
              categories = [
                "Development"
                "Utility"
              ];
              startupNotify = true;
              startupWMClass = "orca";
            })
          ];

          meta = {
            description = "Orca personal fork (Tsuyumi25/orca, personal-use branch)";
            homepage = "https://github.com/Tsuyumi25/orca";
            license = lib.licenses.mit;
            mainProgram = "orca-ai";
            platforms = lib.platforms.linux;
          };
        });
      }
    );
}
