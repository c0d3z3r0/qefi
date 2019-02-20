# qefi

Script for simple booting of Secure Boot signed EFI binaries in qemu mainly for debugging purpose.
I implemented this for testing while debugging/fixing systemd-boot efi handover (see [#11717](https://github.com/systemd/systemd/issues/11717) and [#11772](https://github.com/systemd/systemd/pull/11772)).

## Dependencies

* efitools
* qemu

## License

Copyright (C) 2018 Michael Niewöhner

This is open source software, licensed under GPLv2. See LICENSE file for details.
