# Your work, synced both ways with your Mac by Syncthing: the folders listed
# below, not your whole home (caches, Steam and per-machine config stay put).
# The GUI is at http://127.0.0.1:8384.
{ ... }:
{
  services.syncthing = {
    enable = true;
    # Devices and folders added from the GUI are kept, so pairing the Mac there
    # works before it's listed here.
    overrideDevices = false;
    overrideFolders = false;
    settings = {
      # mac = {
      #   id = "XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX";
      #   addresses = [ "dynamic" ];
      # };
      devices = { };
      # Same folder ID on both machines; the path can differ.
      # projects = {
      #   path = "~/Projects";
      #   devices = [ "mac" ];
      # };
      folders = { };
      options.urAccepted = -1; # no usage reporting
    };
  };
}
