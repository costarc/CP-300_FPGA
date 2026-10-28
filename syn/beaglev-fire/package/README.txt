CP-300 for the BeagleV-Fire
===========================

The Prologica CP-300 (TRS-80 Model III compatible) running in the FPGA of a BeagleV-Fire. The screen, keyboard,
sound and the four floppy drives are in your browser; the board serves the page.

Install
-------
Copy this folder to the board (scp -r, or unpack the tar.gz there) and run, as the user "beagle":

    sudo ./install.sh

It
  - puts the software in /opt/cp300 and starts it at boot (service cp300d),
  - adds the CP-300 to the stock web server (http://<board>/cp300/) and to the Cockpit sidebar (Tools > CP-300),
  - flashes the CP-300 gateware (FPGA bitstream, device tree overlay, bootloader) and reboots the board by itself.
    This takes a couple of minutes: do not power the board off before it is back.

Then open http://<board>/cp300/ and upload the two ROMs once (system ROM, 16384 bytes; character generator,
2048 bytes). They are kept on the board. The ROMs are copyrighted and are not part of this package.
Drop .dsk / .dmk / .hfe / .jv1 / .jv3 images on a drive to mount them.

Another gateware, and back
--------------------------
The CP-300 gateware replaces the one that is in the board's flash. Flashing any other gateware (for example the
stock one: sudo /usr/share/beagleboard/gateware/change-gateware.sh default) replaces it. The software and the
sidebar entry stay, and wait (the service starts only when the CP-300 gateware is loaded).

To use the CP-300 again run the installer once more, or only
    sudo cp300-load-gateware
The installer replaces the installed software and the sidebar entry and flashes the gateware only if it is not
the loaded one (--force-flash flashes it anyway).

Options
-------
  sudo ./install.sh --yes          do not ask before flashing
  sudo ./install.sh --no-flash     software only
  sudo ./install.sh --no-web       gateware only
  sudo ./install.sh --uninstall    remove the software and the sidebar entry (--purge: also the disks and ROMs)
  ./install.sh --check             what is installed and loaded; changes nothing

Warning
-------
Flashing rewrites the whole gateware flash of the board, including the bootloader (HSS). The board's own update
mechanism keeps no fallback copy. If the board does not come back, the way out is the recovery in BeagleBoard's
flashing guide, which needs a FlashPro5/6 programmer. Read VERSION and SOURCE.txt for what was built and from what.

Licence: GNU GPL v3 (file LICENSE). Source: see SOURCE.txt.
