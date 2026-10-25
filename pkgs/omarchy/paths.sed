# Arch paths in Omarchy's scripts and configs -> NixOS paths.
# Applied to every text file under bin/, default/, install/, shell/, config/,
# applications/ of the packaged Omarchy.

# sudo is a setuid wrapper on NixOS; /usr/bin/env exists as-is.
s#/usr/bin/sudo#/run/wrappers/bin/sudo#g
s#/usr/bin/env#@ALLOY_ENV@#g

# Commands by absolute path.
s#/usr/s\?bin/#/run/current-system/sw/bin/#g

# /usr/bin as a directory, e.g. a fixed PATH in a script that runs as root
# (PATH=/usr/local/bin:/usr/bin). On NixOS that is the setuid wrappers plus the
# system profile, both root-owned.
s#/usr/s\?bin\([:"' )]\)#/run/wrappers/bin:/run/current-system/sw/bin\1#g
s#/usr/s\?bin$#/run/wrappers/bin:/run/current-system/sw/bin#

s#@ALLOY_ENV@#/usr/bin/env#g

# /bin/bash (NixOS only has /bin/sh).
s#\([^A-Za-z0-9_./-]\)/bin/bash\b#\1/run/current-system/sw/bin/bash#g
s#^/bin/bash\b#/run/current-system/sw/bin/bash#

# Libraries, user units, shared data. /usr/share/omarchy itself stays: alloy
# installs Omarchy there.
s#/usr/lib/systemd/user/#/etc/systemd/user/#g
s#/usr/lib/#/run/current-system/sw/lib/#g
s#/usr/share/omarchy#@ALLOY_OMARCHY@#g
s#/usr/share/#/run/current-system/sw/share/#g
s#@ALLOY_OMARCHY@#/usr/share/omarchy#g
