{
  description = "Windscribe GUI client flake with NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; 
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      windscribePkgs = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;
          runtimeDeps = with pkgs; [ 
            nftables c-ares freetype hicolor-icon-theme systemd glibc glib zlib
            dbus libglvnd fontconfig xorg.libX11 libxkbcommon xorg.libxcb
            nettools xorg.xcbutilwm xorg.xcbutilimage xorg.xcbutilkeysyms
            xorg.xcbutilrenderutil sudo shadow stdenv.cc.cc.lib libnl
            libcap_ng wayland xorg.xcbutilcursor
            qt6.qtbase qt6.qtwayland qt6.qtsvg
          ];
        in
        stdenv.mkDerivation rec {
          pname = "windscribe-v2-bin";
          version = "2.14.10";
          src = pkgs.fetchurl {
            url = "https://deploy.totallyacdn.com/desktop-apps/${version}/windscribe_${version}_x86_64.pkg.tar.zst";
            hash = "sha256-Ijho19vbmqM25MvSFxavtXwwI/abjOO9ZNrWV0n8SmA=";
          };

          nativeBuildInputs = [ 
            pkgs.zstd pkgs.autoPatchelfHook pkgs.makeWrapper pkgs.pkg-config
            pkgs.gnused pkgs.findutils
          ];
          buildInputs = runtimeDeps;
          dontWrapQtApps = true; 
          dontStrip = true;
          dontConfigure = true;
          dontBuild = true;

          unpackPhase = ''
            zstd -d < $src | tar x --no-same-owner
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin

            echo "Copying extracted files to $out..."
            cp -a ./etc $out/ || echo "No etc directory found, skipping."
            cp -a ./opt $out/ || echo "No opt directory found, skipping."
            if [ -d ./usr ]; then cp -a ./usr/* $out/; else echo "No usr directory found, skipping."; fi

            local service_file="$out/lib/systemd/system/windscribe-helper.service"
            if [ -f "$service_file" ]; then chmod -x "$service_file"; else echo "Systemd service file not found, skipping chmod."; fi

            # Define paths
            main_executable="$out/opt/windscribe/Windscribe"
            # This wrapper just sets the PATH, it doesn't need setgid itself
            wrapper_path="$out/bin/$pname"
            export wrapper_path

            # --- Create PATH Wrapper ---
            # This wrapper ensures sudo, nftables etc are in PATH
            if [ -f "$main_executable" ]; then
              echo "Creating PATH wrapper for $main_executable at $wrapper_path"
              makeWrapper "$main_executable" "$wrapper_path" \
                --prefix PATH : ${lib.makeBinPath [ pkgs.sudo pkgs.nettools pkgs.dbus pkgs.nftables pkgs.shadow ]}
            else
             echo "Error: Main executable not found for wrapping at $main_executable"; exit 1;
            fi

            # --- Patch .desktop files ---
            # Patch Exec= to point to the PATH wrapper ($wrapper_path)
            # The NixOS module will later override this to point to the setgid wrapper
            echo "Patching .desktop files..."
            find $out/share/applications -name "*.desktop" -type f -print0 | while IFS= read -r -d $'\0' f; do
              echo "  Patching $f to use $wrapper_path"
              substituteInPlace "$f" --replace "Exec=/opt/windscribe/Windscribe" "Exec=$wrapper_path"
              substituteInPlace "$f" --replace "TryExec=/opt/windscribe/Windscribe" "TryExec=$wrapper_path"
            done
            if ! compgen -G "$out/share/applications/*.desktop" > /dev/null; then
               echo "Warning: No .desktop files found to patch in $out/share/applications"
            fi

            runHook postInstall
          '';

          meta = {
            description = "Windscribe GUI tool for Linux";
            homepage = "https://windscribe.com/guides/linux";
            license = lib.licenses.gpl2Only;
            platforms = lib.platforms.linux;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            maintainers = with lib.maintainers; [ ItzDerock ];
          };
        }); 

      windscribeModule = ({ config, pkgs, lib, ... }:
        let
          cfg = config.services.windscribe;
          setgidWrapperName = "windscribe-gui";
          setgidWrapperPath = "/run/wrappers/bin/${setgidWrapperName}";
        in
        {
          options.services.windscribe = {
            enable = lib.mkEnableOption "Windscribe VPN GUI, CLI, and Helper Service";
            package = lib.mkOption {
              type = lib.types.package;
              default = windscribePkgs.${pkgs.system};
              description = "Which Windscribe package derivation to use.";
            };
          };

          config = lib.mkIf cfg.enable {
            users.groups.windscribe = {};
            environment.systemPackages = [ cfg.package ];

            # Define and enable the systemd service
            systemd.services.windscribe-helper = {
              description = "Windscribe Helper Service";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${cfg.package}/opt/windscribe/helper";
                Group = "windscribe";
                Restart = "on-failure";
              };
            };

            # Define the setgid security wrapper
            security.wrappers.${setgidWrapperName} = {
              owner = "root";
              group = "windscribe"; 
              permissions = "u=rx,g=rxs,o="; 
              setgid = true;
              source = "${cfg.package}/bin/${cfg.package.pname}";
            };

            # 5. Override the .desktop file's Exec key
            # xdg.desktopEntries.windscribe = {
            #   source = "${cfg.package}/share/applications/windscribe.dekstop";
            #   desktopEntry = {
            #     Exec = "${setgidWrapperPath} %U"; 
            #     TryExec = "${setgidWrapperPath}"; 
            #   };
            # };

            # Add Qt platform plugin paths
            environment.sessionVariables = {
              QT_PLUGIN_PATH = lib.makeSearchPathOutput "lib" "qt-6/plugins" [
                pkgs.qt6.qtbase
                pkgs.qt6.qtwayland
              ];
            };
          };
        }); 

    in 
    { 
      packages = forAllSystems (system: {
         windscribe-v2-bin = windscribePkgs.${system};
         default = windscribePkgs.${system};
      });
      nixosModules.default = windscribeModule;
    }; 
} 

