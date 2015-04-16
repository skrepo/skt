Tcl and Tk dependencies
======================

# ldd base-tk-8.6.3.1 
    linux-vdso.so.1 =>  (0x00007fff783fe000)
    libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f935988e000)
    libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007f9359675000)
    libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f9359370000)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f9358fa8000)
    /lib64/ld-linux-x86-64.so.2 (0x00007f9359ac0000)

base-tk has only libc dependencies directly

In order to see the real (X11) dependencies we need to examine tk.so library:

./base-tcl-linux sdx.kit unwrap base-tk-8.6.3.1

# ldd libtk8.6.so 
    linux-vdso.so.1 =>  (0x00007ffff6dfe000)
    libXft.so.2 => /usr/lib/x86_64-linux-gnu/libXft.so.2 (0x00007f52e8518000)
    libX11.so.6 => /usr/lib/x86_64-linux-gnu/libX11.so.6 (0x00007f52e81e2000)
    libfreetype.so.6 => /usr/lib/x86_64-linux-gnu/libfreetype.so.6 (0x00007f52e7f40000)
    libfontconfig.so.1 => /usr/lib/x86_64-linux-gnu/libfontconfig.so.1 (0x00007f52e7d04000)
    libXrender.so.1 => /usr/lib/x86_64-linux-gnu/libXrender.so.1 (0x00007f52e7af9000)
    libXss.so.1 => /usr/lib/x86_64-linux-gnu/libXss.so.1 (0x00007f52e78f5000)
    libXext.so.6 => /usr/lib/x86_64-linux-gnu/libXext.so.6 (0x00007f52e76e3000)
    libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f52e74de000)
    libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007f52e72c5000)
    libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f52e6fc1000)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f52e6bf8000)
    libxcb.so.1 => /usr/lib/x86_64-linux-gnu/libxcb.so.1 (0x00007f52e69da000)
    libexpat.so.1 => /lib/x86_64-linux-gnu/libexpat.so.1 (0x00007f52e67b0000)
    libpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007f52e6592000)
    /lib64/ld-linux-x86-64.so.2 (0x00007f52e89ac000)
    libXau.so.6 => /usr/lib/x86_64-linux-gnu/libXau.so.6 (0x00007f52e638e000)
    libXdmcp.so.6 => /usr/lib/x86_64-linux-gnu/libXdmcp.so.6 (0x00007f52e6187000)


Of the above the relevant ones (non-libc):

libXft.so.2             apt-get install libxft2
libX11.so.6             apt-get install libx11-6
libfreetype.so.6        apt-get install libfreetype6
libfontconfig.so.1      apt-get install libfontconfig1
libXrender.so.1         apt-get install libxrender1
libXss.so.1             apt-get install libxss1
libXext.so.6            apt-get install libxext6
libz.so.1               apt-get install zlib1g
libxcb.so.1             apt-get install libxcb1
libexpat.so.1           apt-get install libexpat1
libXau.so.6             apt-get install libxau6
libXdmcp.so.6           apt-get install libxdmcp6


TLS dependencies
================

# ldd libtls1.6.4.so 
    linux-vdso.so.1 =>  (0x00007fffdfffe000)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f0dbf32a000)
    /lib64/ld-linux-x86-64.so.2 (0x00007f0dbfa51000)

It looks like tls is statically linked against openssl so no dependencies except libc


OpenVPN dependencies
======================

This openvpn on my Ubuntu was compiled manually and it looks like no dep on libssl:

# l $(which openvpn)
-rwxr-xr-x 1 root staff 5161690 Aug 31  2014 /usr/local/sbin/openvpn
# ldd $(which openvpn)
    linux-vdso.so.1 =>  (0x00007fff29719000)
    liblzo2.so.2 => /lib/x86_64-linux-gnu/liblzo2.so.2 (0x00007f5fabf3a000)
    libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f5fabd36000)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f5fab96d000)
    /lib64/ld-linux-x86-64.so.2 (0x00007f5fac189000)


This rpm was built from source with rpmbuild:
rpmbuild -tb openvpn-2.3.6.tar.gz 

[root@localhost x86_64]# ls -l usr/sbin/openvpn 
-rwxr-xr-x. 1 root root 709418 Apr 13 21:40 usr/sbin/openvpn
[root@localhost x86_64]# ldd usr/sbin/openvpn 
	linux-vdso.so.1 =>  (0x00007fff4fac2000)
	libnsl.so.1 => /lib64/libnsl.so.1 (0x00007f3e60348000)
	libresolv.so.2 => /lib64/libresolv.so.2 (0x00007f3e6012e000)
	liblzo2.so.2 => /lib64/liblzo2.so.2 (0x00007f3e5ff0b000)
	libssl.so.10 => /lib64/libssl.so.10 (0x00007f3e5fc9c000)
	libcrypto.so.10 => /lib64/libcrypto.so.10 (0x00007f3e5f8af000)
	libdl.so.2 => /lib64/libdl.so.2 (0x00007f3e5f6aa000)
	libc.so.6 => /lib64/libc.so.6 (0x00007f3e5f2ed000)
	libgssapi_krb5.so.2 => /lib64/libgssapi_krb5.so.2 (0x00007f3e5f0a0000)
	libkrb5.so.3 => /lib64/libkrb5.so.3 (0x00007f3e5edbc000)
	libcom_err.so.2 => /lib64/libcom_err.so.2 (0x00007f3e5ebb8000)
	libk5crypto.so.3 => /lib64/libk5crypto.so.3 (0x00007f3e5e985000)
	libz.so.1 => /lib64/libz.so.1 (0x00007f3e5e76e000)
	/lib64/ld-linux-x86-64.so.2 (0x00007f3e6057d000)
	libkrb5support.so.0 => /lib64/libkrb5support.so.0 (0x00007f3e5e55f000)
	libkeyutils.so.1 => /lib64/libkeyutils.so.1 (0x00007f3e5e35b000)
	libpthread.so.0 => /lib64/libpthread.so.0 (0x00007f3e5e13e000)
	libselinux.so.1 => /lib64/libselinux.so.1 (0x00007f3e5df19000)
	libpcre.so.1 => /lib64/libpcre.so.1 (0x00007f3e5dcab000)
	liblzma.so.5 => /lib64/liblzma.so.5 (0x00007f3e5da86000)





# rpm dependecies
[root@localhost x86_64]# rpm -qpR  openvpn-2.3.6-1.x86_64.rpm 
/bin/sh
/bin/sh
lzo >= 1.07
openssl >= 0.9.7
pam
rpmlib(CompressedFileNames) <= 3.0.4-1
rpmlib(FileDigests) <= 4.6.0-1
rpmlib(PayloadFilesHavePrefix) <= 4.0-1
rpmlib(PayloadIsXz) <= 5.2-1


# openvpn from rpm package built by rpmbuild on Fedora when run on Ubuntu:
# ./openvpn 
./openvpn: error while loading shared libraries: libssl.so.10: cannot open shared object file: No such file or directory

This is getting messy. Solution: use openvpn provided by OS package manager, and add dependency in deb/rpm package. Check openvpn and openssl version in SKD/SKU

