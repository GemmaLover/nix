{ config, pkgs, ... }:

{
  imports = [
    ./unsloth.nix
    ./deepseek-harness.nix
    ./cockpit.nix
    ./cockpit-toolboxes.nix
    ./gufo.nix
  ];
}
