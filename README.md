BASHare
=======

Utility that conveniently serves the current directory + all subdirectory from a webserver.

Requires the utility `socat` or `netcat`. netcat does not allow for multiple simultaneous TCP connections, install socat for multi user support. If both are installed, bashare will use socat by default to utilize all features. `file` is needed to detect the correct MIME types.

Features:
---------
* share files on a small local webserver
* supports HTTP compression (gzip)
* compatible with socat and netcat
* download folders as archive

Install:
--------
1. download the script and grant executable rights `chmod +x /PATH/TO/SCRIPT/bashare.sh` 
2. open `.bashrc` in a texteditor of your choice
3. add a new line:  `bashare() { /PATH/TO/SCRIPT/bashare.sh "$@" ;}`

Usage:
------
1. run `bashare`
