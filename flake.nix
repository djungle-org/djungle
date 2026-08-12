{
  description = "zig vulkan engine dev shell";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls/0.16.0";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.zig-overlay.follows = "zig-overlay";
  };
  outputs =
    {
      self,
      nixpkgs,
      zig-overlay,
      zls,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      zig = zig-overlay.packages.${system}."0.16.0";
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          vulkan-headers
          vulkan-loader
          vulkan-validation-layers
          vulkan-tools
          vulkan-tools-lunarg
          shaderc
          shader-slang
          sdl3
          gdb
          renderdoc
        ];
        nativeBuildInputs = [
          zig
          zls.packages.${system}.zls
          pkgs.pkg-config
        ];

        shellHook = ''
          export VK_LAYER_PATH=${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d
          export VK_ADD_LAYER_PATH=$VK_LAYER_PATH
          export LD_LIBRARY_PATH=${pkgs.vulkan-loader}/lib:${pkgs.renderdoc}/lib:$LD_LIBRARY_PATH
          export VULKAN_REGISTRY_XML=${pkgs.vulkan-headers}/share/vulkan/registry/vk.xml
        '';
      };
    };
}
