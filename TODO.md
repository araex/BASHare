TODO
----
* Support 7z for download archive.
* Cache MIME-type information for files due to bad performance of `file --mime-type`.
* Add call parameters to:
    * disable MIME-type detection for improved performance.
    * customize download archive option.

ISSUES
------
* Download archive does not work if called for a hidden directory since tar -c fails with hidden files only.
* Does not work with gnu-netcat. 
* Check for gnu-netcat breaks openbsd-netcat.
* Can't maintain multiple tcp connections when in netcat mode.
* Even if hidden files are not listed, they can still be downloaded if entered manually in URL.
