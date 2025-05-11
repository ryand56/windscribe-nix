# flake.nix
{
  description = "Windscribe GUI client flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or choose a specific branch/tag
  };

  outputs = { self, nixpkgs }:
    let
      # We only support x86_64-linux as per the PKGBUILD
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    { # Start of outputs attrset
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;

          # Map Arch dependencies to Nixpkgs attributes
          runtimeDeps = with pkgs; [
            # Original dependencies
            nftables
            c-ares
            freetype
            hicolor-icon-theme
            systemd
            glibc
            glib
            zlib
            dbus
            libglvnd
            fontconfig
            xorg.libX11
            libxkbcommon
            xorg.libxcb # Use the default output, not .dev
            nettools
            xorg.xcbutilwm
            xorg.xcbutilimage
            xorg.xcbutilkeysyms
            xorg.xcbutilrenderutil
            sudo
            shadow
            stdenv.cc.cc.lib

            # Dependencies identified by autoPatchelfHook
            libnl
            libcap_ng
            wayland
            xorg.xcbutilcursor # Provides libxcb-cursor.so.0
          ];

          windscribePkg = stdenv.mkDerivation rec {
            pname = "windscribe-v2-bin";
            version = "2.14.10";

            src = pkgs.fetchurl {
              url = "https://deploy.totallyacdn.com/desktop-apps/${version}/windscribe_${version}_x86_64.pkg.tar.zst";
              hash = "sha256-Ijho19vbmqM25MvSFxavtXwwI/abjOO9ZNrWV0n8SmA=";
            };

            nativeBuildInputs = [
              pkgs.zstd # To unpack .tar.zst
              pkgs.autoPatchelfHook # To fix library paths in binaries
              pkgs.makeWrapper # May be needed for runtime PATH adjustments
              pkgs.pkg-config # Often needed by autoPatchelfHook
            ];

            # These are runtime libraries/dependencies needed by the binaries
            buildInputs = runtimeDeps;

            # Replicate options = ('!strip')
            dontStrip = true;

            # This isn't source code, skip configure/build phases
            dontConfigure = true;
            dontBuild = true;

            unpackPhase = ''
              # Extract the Arch package (.pkg.tar.zst)
              # Using --no-same-owner to avoid potential permission issues
              zstd -d < $src | tar x --no-same-owner
            '';

            installPhase = ''
              runHook preInstall

              # Create the output directory structure
              # Ensure bin directory exists first for the wrapper
              mkdir -p $out/bin

              # Copy contents from the extracted archive to $out
              echo "Copying extracted files to $out..."
              cp -a ./etc $out/ || echo "No etc directory found, skipping."
              cp -a ./opt $out/ || echo "No opt directory found, skipping."
              if [ -d ./usr ]; then
                cp -a ./usr/* $out/
              else
                echo "No usr directory found, skipping."
              fi

              # Fix permissions on systemd unit
              local service_file="$out/lib/systemd/system/windscribe-helper.service"
              if [ -f "$service_file" ]; then
                echo "Fixing permissions on $service_file"
                chmod -x "$service_file"
              else
                echo "Systemd service file not found at $service_file, skipping chmod."
              fi

              # --- Create Wrapper ---
              # Path confirmed from 'ls' output
              local main_executable="$out/opt/windscribe/Windscribe"
              # Define the target path for the wrapper script
              local wrapper_path="$out/bin/${pname}"

              if [ -f "$main_executable" ]; then
                echo "Creating wrapper for $main_executable at $wrapper_path"
                # Use makeWrapper directly:
                # makeWrapper <executable_to_wrap> <output_wrapper_path> --flags...
                makeWrapper "$main_executable" "$wrapper_path" \
                  --prefix PATH : ${lib.makeBinPath [ pkgs.sudo pkgs.nettools pkgs.dbus pkgs.nftables pkgs.shadow ]}

                # makeWrapper should set executable permissions automatically, so chmod isn't needed here.
              else
               echo "Error: Main executable not found for wrapping at $main_executable"
               exit 1 # Fail the build if we can't find the executable
              fi

              # Note: Other executables like windscribe-cli, windscribectrld etc.
              # are not wrapped by default. If you need to run them directly
              # from the PATH, they would need their own wrappers created here,
              # potentially placed in $out/bin as well (e.g., $out/bin/windscribe-cli).

              runHook postInstall
            '';


            meta = {
              description = "Windscribe GUI tool for Linux";
              homepage = "https://windscribe.com/guides/linux";
              license = lib.licenses.gpl2Only;
              platforms = lib.platforms.linux;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              # maintainers = with lib.maintainers; [ yourGithubUsername ];
            };
          };
        in
        {
          windscribe-v2-bin = windscribePkg;
          default = windscribePkg;
        }); # End forAllSystems

      # nixosModules.default = { ... };

    }; # End outputs attrset
} # End flake definition

