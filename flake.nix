{
  description = "Lian Li Linux - open-source Linux replacement for L-Connect 3";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    # Linux-only hardware-control project (matches upstream's own
    # arch=('x86_64') in packaging/archlinux/PKGBUILD).
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        lib = pkgs.lib;

        version = "1.1.1";

        # Only the four binaries that upstream ships (matches the Debian,
        # Fedora and Arch packaging); lianli-gui-old is excluded from the
        # workspace and the *-probe / render-preview dev binaries aren't
        # part of the shipped product.
        lianliCrateFlags = [
          "-p" "lianli-daemon"
          "-p" "lianli-gui"
          "-p" "lianli-session"
          "-p" "lianli-control"
        ];

        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        # Vendored git submodules (vendor/tinyuz, vendor/HDiffPatch) are not
        # part of a plain source checkout, so fetch the pinned commits
        # directly. Kept in sync with .gitmodules / `git submodule status`.
        tinyuzSrc = pkgs.fetchFromGitHub {
          owner = "sisong";
          repo = "tinyuz";
          rev = "1d74ffa4d453796df352df470733f45dfa099bb1";
          hash = "sha256-3z4Plo3ANxP2PuBPD/Qutjk7Qi+Qs6ufpUJojThEuMY=";
        };
        hdiffpatchSrc = pkgs.fetchFromGitHub {
          owner = "sisong";
          repo = "HDiffPatch";
          rev = "3b9dca715ca492873bf2c49e22e5d5b7d2a78620";
          hash = "sha256-8bDefNdKO9bLJzENY1OEap7tTSzI7C/oUECgXBJSiEE=";
        };

        # The Tauri GUI embeds a Vue/Vite frontend. `src-tauri/build.rs`
        # refuses to invoke `npm` itself unless the checked-in sources and
        # `dist/` output diverge from `dist/.lianli-build.json`, so the
        # frontend has to be built ahead of time and dropped into place
        # (see crates/lianli-gui/src-tauri/build/frontend.rs).
        frontend = pkgs.buildNpmPackage {
          pname = "lianli-gui-frontend";
          inherit version;
          src = ./crates/lianli-gui;

          npmDepsFetcherVersion = 2;
          npmDepsHash = "sha256-dZNQsibswi0Urn4qW6foUKzBTZXHG0WplpSkm2y7RT0=";

          npmBuildScript = "build";

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r dist/. $out/
            runHook postInstall
          '';
        };

        lian-li-linux = rustPlatform.buildRustPackage {
          pname = "lian-li-linux";
          inherit version;
          src = self;

          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [
            pkg-config
            cmake
            nasm
            rustPlatform.bindgenHook
            wrapGAppsHook3
          ];

          buildInputs = with pkgs; [
            libusb1
            udev
            ffmpeg
            fontconfig
            libxkbcommon
            wayland
            libGL
            libinput
            libdrm
            libx11
            gtk3
            glib
            webkitgtk_4_1
            libsoup_3
            libayatana-appindicator
            librsvg
          ];

          postPatch = ''
            rm -rf vendor/tinyuz vendor/HDiffPatch
            cp -r ${tinyuzSrc} vendor/tinyuz
            cp -r ${hdiffpatchSrc} vendor/HDiffPatch
            chmod -R u+w vendor/tinyuz vendor/HDiffPatch

            rm -rf crates/lianli-gui/dist
            cp -r ${frontend} crates/lianli-gui/dist
            chmod -R u+w crates/lianli-gui/dist
          '';

          cargoBuildFlags = lianliCrateFlags;
          cargoTestFlags = lianliCrateFlags;

          # The workspace test suite expects real hardware/USB devices and a
          # writable D-Bus/systemd session; skip it for a hermetic package
          # build (same as the reasoning for `cargo build`-only CI images).
          doCheck = false;

          env.CARGO_PROFILE_RELEASE_STRIP = "symbols";

          postInstall = ''
            install -Dm644 packaging/systemd/lianli-session.service \
              $out/lib/systemd/user/lianli-session.service
            install -Dm644 packaging/systemd/lianli-daemon.service \
              $out/lib/systemd/user/lianli-daemon.service
            install -Dm644 packaging/systemd/lianli-daemon-system.service \
              $out/lib/systemd/system/lianli-daemon-system.service
            install -Dm644 packaging/systemd/lianli-control-recovery.service \
              $out/lib/systemd/system/lianli-control-recovery.service

            install -Dm644 packaging/udev/60-lianli.rules \
              $out/lib/udev/rules.d/60-lianli.rules

            install -Dm644 packaging/sysusers.d/lianli.conf \
              $out/lib/sysusers.d/lianli.conf
            install -Dm644 packaging/tmpfiles.d/lianli.conf \
              $out/lib/tmpfiles.d/lianli.conf

            install -Dm644 packaging/polkit/49-lianli-recovery.rules \
              $out/share/polkit-1/rules.d/49-lianli-recovery.rules

            install -Dm644 packaging/desktop/com.sgtaziz.lianlilinux.desktop \
              $out/share/applications/com.sgtaziz.lianlilinux.desktop
            install -Dm644 packaging/desktop/com.sgtaziz.lianlilinux.session.desktop \
              $out/etc/xdg/autostart/com.sgtaziz.lianlilinux.session.desktop
            install -Dm644 packaging/desktop/com.sgtaziz.lianlilinux.recovery.desktop \
              $out/etc/xdg/autostart/com.sgtaziz.lianlilinux.recovery.desktop
            install -Dm644 packaging/desktop/com.sgtaziz.lianlilinux.metainfo.xml \
              $out/share/metainfo/com.sgtaziz.lianlilinux.metainfo.xml

            install -Dm644 assets/icons/32x32.png \
              $out/share/icons/hicolor/32x32/apps/com.sgtaziz.lianlilinux.png
            install -Dm644 assets/icons/128x128.png \
              $out/share/icons/hicolor/128x128/apps/com.sgtaziz.lianlilinux.png
            install -Dm644 assets/icons/128x128@2x.png \
              $out/share/icons/hicolor/256x256/apps/com.sgtaziz.lianlilinux.png
            install -Dm644 assets/icons/icon.svg \
              $out/share/icons/hicolor/scalable/apps/com.sgtaziz.lianlilinux.svg

            install -d $out/share/man/man1
            install -m644 packaging/man/*.1 $out/share/man/man1/

            install -Dm644 LICENSE $out/share/licenses/lian-li-linux/LICENSE
            install -Dm644 crates/lianli-display/src/hermes/UAPI-LICENSE \
              $out/share/licenses/lian-li-linux/Hermes-KMS-UAPI-LICENSE
            install -Dm644 vendor/tinyuz/LICENSE \
              $out/share/licenses/lian-li-linux/tinyuz-LICENSE
            install -Dm644 vendor/HDiffPatch/LICENSE \
              $out/share/licenses/lian-li-linux/HDiffPatch-LICENSE
          '';

          meta = with lib; {
            description = "Fan speed, RGB/LED and LCD control daemon and desktop app for Lian Li hardware";
            homepage = "https://github.com/sgtaziz/lian-li-linux";
            license = with licenses; [ mit gpl2Only ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "lianli-gui";
          };
        };
      in
      {
        packages = {
          default = lian-li-linux;
          lian-li-linux = lian-li-linux;
          inherit frontend;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = lian-li-linux;
            name = "lianli-gui";
          };
          lianli-gui = flake-utils.lib.mkApp {
            drv = lian-li-linux;
            name = "lianli-gui";
          };
          lianli-daemon = flake-utils.lib.mkApp {
            drv = lian-li-linux;
            name = "lianli-daemon";
          };
          lianli-session = flake-utils.lib.mkApp {
            drv = lian-li-linux;
            name = "lianli-session";
          };
          lianli-control = flake-utils.lib.mkApp {
            drv = lian-li-linux;
            name = "lianli-control";
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ lian-li-linux ];
          packages = with pkgs; [
            nodejs
            rustToolchain
            clippy
            rust-analyzer
          ];

          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
        };
      }) // {
      nixosModules.default = { pkgs, lib, ... }: {
        imports = [ ./packaging/nixos/module.nix ];
        config.services.lianli-linux.package =
          lib.mkDefault self.packages.${pkgs.system}.default;
      };
    };
}
