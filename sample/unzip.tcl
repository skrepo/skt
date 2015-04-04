package require vfs::zip


proc unzip {zipfile {destdir .}} {
  set mntfile [vfs::zip::Mount $zipfile $zipfile]
  foreach f [glob $zipfile/*] {
    file copy $f $destdir
  }
  vfs::zip::Unmount $mntfile $zipfile
}

unzip {*}$argv
