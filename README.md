# Windscribe on NixOS

an attempt to get Windscribe running on NixOS. Does not compile from source, instead downloads and patches the binary.

> [!NOTE] WORK IN PROGRESS! Instructions below are subject to change, and this module is still not fully functional yet.

## Features

*   Packages the official Windscribe x86_64 binary (`.pkg.tar.zst`).
*   Includes a NixOS module for simple configuration:
    *   Creates the necessary `windscribe` system group.
    *   Installs the Windscribe package.
    *   Sets up and enables the `windscribe-helper` systemd service.
    *   Configures a setgid security wrapper to allow the GUI to run with the correct group permissions.
    *   Patches the `.desktop` file to use the security wrapper.
    *   Sets `QT_PLUGIN_PATH` for potentially better Qt integration.
*   The GUI application is launched via a security wrapper, allowing it to acquire the necessary group privileges without running the entire application as root.

## Installation

1.  **Add the Flake to Your NixOS Configuration:**

    Open your system's `flake.nix` (e.g., `/etc/nixos/flake.nix`) and add this repository as an input:

    ```nix
    # /etc/nixos/flake.nix
    {
      description = "My NixOS Configuration";

      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or your preferred branch

        # Add this flake
        windscribe-bin = {
          url = "github:itzderock/windscribe-nix"; # Or path:/path/to/local/repo
          inputs.nixpkgs.follows = "nixpkgs"; 
        };

        # ... other inputs like home-manager etc.
      };

      outputs = { self, nixpkgs, windscribe-bin, ... }@inputs: {
        nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; }; # Pass inputs to modules
          modules = [
            ./configuration.nix
            # Potentially add home-manager modules etc.
          ];
        };
      };
    }
    ```

2.  **Enable the Windscribe Service in Your `configuration.nix`:**

    Open your main NixOS configuration file and:
    *   Import the module.
    *   Enable the service.
    *   Manually add your user to the `windscribe` group.

    ```nix
    { config, pkgs, inputs, ... }: # Make sure 'inputs' is available

    {
      imports = [
        inputs.windscribe-bin.nixosModules.default # Import the module
        # ... other imports
      ];

      # Enable Windscribe
      services.windscribe.enable = true;

      # Manually add your user to the 'windscribe' group
      users.users.your_username = { # Replace 'your_username'
        # ... other user settings ...
        extraGroups = [ /* other groups */ "windscribe" ];
      };

      # ... rest of your system configuration ...
    }
    ```

3.  **Rebuild Your NixOS System**
4.  **Log Out and Log Back In.** 

## How it Works

The Windscribe GUI application requires the ability to set its group ID to `windscribe`. To achieve this without running the entire GUI as root or using a traditional setgid binary in the Nix store (which is discouraged), this flake's NixOS module employs a **security wrapper**:

1.  A `makeWrapper` script (`$out/bin/windscribe-v2-bin`) is created for the main Windscribe executable (`$out/opt/windscribe/Windscribe`). This wrapper primarily sets up the `PATH` to include necessary tools like `sudo`, `nftables`, etc.
2.  The NixOS module defines a **security wrapper** (`/run/wrappers/bin/windscribe-gui`). This wrapper is:
    *   Owned by `root:windscribe`.
    *   Has the `setgid` bit (`g+s`).
    *   Its source (the command it executes) is the `makeWrapper` script mentioned above.
3.  The `.desktop` file for Windscribe is modified by the NixOS module to execute this `/run/wrappers/bin/windscribe-gui` security wrapper.

When you launch Windscribe from your desktop environment:
*   The security wrapper is executed.
*   Due to the `setgid` bit, the process gains the `windscribe` group's effective GID.
*   The security wrapper then runs the `makeWrapper` script (which sets up the `PATH`).
*   The `makeWrapper` script finally runs the actual Windscribe GUI binary.
*   The Windscribe GUI, now running with the `windscribe` effective GID, can successfully call `setgid()` and initialize.

The `windscribe-helper` systemd service is also configured to run with the `windscribe` group, allowing for proper communication and privileged operations.

## Contributing

Contributions are welcome! Please open an issue or pull request.

## License

The Nix packaging code in this repository is available under a permissive license (MIT). The Windscribe software itself is under it's own license, which you can find at https://github.com/Windscribe/Desktop-App/blob/master/LICENSE
