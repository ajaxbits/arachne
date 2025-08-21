{ lib, ... }:
{
  options.components.monitoring = {
    enable = lib.mkEnableOption "Enable the monitoring stack.";
  };
}
