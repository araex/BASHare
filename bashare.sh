#! /bin/bash
# BASHare is a utility that shares the currently open directory on a built in webserver
# dependencies: 'socat' or 'netcat'* 
# *netcat does not offer multiple simultanious connections

__init(){	
	[ $UID == 0 ] && echo "You shouldn\'t run this script with root privileges..."
	command -v socat >/dev/null 2>&1 && SOCAT="true"
	command -v netcat >/dev/null 2>&1 && NETCAT="true"

	__parse_Args $@

	if [ $SOCAT ]
	then
		echo "Using socat. Directory '${PWD}' is now available on port ${BSHR_PORT}"
		DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
		export BSHR_SOCAT_CALL="true"
		socat TCP4-LISTEN:${BSHR_PORT},fork EXEC:"${DIR}/bashare.sh"

	elif [ $NETCAT ]
	then
		IOPIPE=/tmp/basharepipe
		[ -p $IOPIPE ] || mkfifo $IOPIPE
		echo "Using netcat. Directory '${PWD}' is now available on port ${BSHR_PORT}"
		while true
		do
			nc -l "${BSHR_PORT}" 0<$IOPIPE | (__read) 1>$IOPIPE
		done
	else
		echo "Couldn't locate netcat or socat, aborting."
		exit 1
	fi	
}	

# parse command line arguments, export them for socat use
__parse_Args(){
	export BSHR_PORT=8000
	while getopts "p:hr" opt; do
  		case $opt in
    			p)
      				BSHR_PORT=$OPTARG
      			;;
			h)
				__showHelp $0
			;;
			r)
				echo "NOT IMPLEMENTED YET. Show only current directory, no subdirectories."
			;;	
    			\?)
      				echo "Invalid option: -$OPTARG" >&2
      			;;
  		esac
	done

}

__showHelp(){
	echo "Usage: `basename $1`: [-p port]"
	echo "  -p: port to use"
	echo "  -r: only serve current directory, no subdircetories"
	echo "  -h: show this help"
}

# HTTP request interprer
__read(){
	REQ=""
	while read L && [ " " "<" "$L" ]; do 
		REQ=${REQ}${L} 
	done
	#echo -e "================\nHTTP REQUEST: $REQ\n">&2
	REQMETHOD=($(echo "$REQ" | grep "GET"))

	case ${REQMETHOD[0]} in
		GET)
			URL=${PWD}${REQMETHOD[1]}
			URL=${URL//'%20'/ }
			if   [[ $URL == */ ]] #is dir 
			then
				send_header 200 "text/html"
				send_directory_index "${URL}"
			elif [ -f "${URL}" ]
			then 
				send_header 200 $(file --mime-type "${URL}" | sed 's#.*:\ ##') $(stat -c%s "${URL}")
				cat "${URL}"
			else send_response 404
			fi
			;;
		*)
			send_response 418
			;;
	esac
}

# send http header
# $1 = http response code
# $2 = [optional] mime-type
# $3 = [optional] content-length
send_header(){
	echo "HTTP/1.1 $1 ${HTTP_RESPONSE[$1]}"
	echo "Server: bashare.sh"
	echo "Content-Type: ${2-"text/plain"}; charset=UTF-8"
	echo "Connection: close"
	echo "Accept-Ranges: bytes"
	echo "Content-Length: $3" 
	echo -en "\r\n"
}

declare -a HTTP_RESPONSE=(
	[200]="OK"
	[400]="Bad Request"
	[403]="Forbidden"
	[404]="Not Found"
	[405]="Method Not Allowed"
	[418]="I\'m a teapot"
	[500]="Internal Server Error"
)

# generate directory index
# $1 path of directory
send_directory_index(){

# CSS courtesy of Jochen Kupperschmidt
# http://homework.nwsnet.de/releases/4f27/
cat <<'EOF1'
<html>
  <head>
    <meta charset="utf-8"/>
    <style>
      body {
        background-color: #eeeeee;
        font-family: Verdana, Arial, sans-serif;
        font-size: 90%;
        margin: 4em 0;
      }

      article,
      footer {
        display: block;
        margin: 0 auto;
        width: 80%;
      }

      a {
        color: #004466;
        text-decoration: none;
      }
      a:hover {
        text-decoration: underline;
      }
      a:visited {
        color: #666666;
      }

      article {
        background-color: #ffffff;
        border: #cccccc solid 1px;
        -moz-border-radius: 11px;
        -webkit-border-radius: 11px;
        border-radius: 11px;
        padding: 0 1em;
      }
      h1 {
        font-size: 140%;
      }
      ol {
        line-height: 1.4em;
        list-style-type: disc;
      }
      li.directory a:before {
        content: '[ ';
      }
      li.directory a:after {
        content: ' ]';
      }

      footer {
        font-size: 70%;
        text-align: center;
      }
    </style>
    <title>Directory Index</title>
  </head>
  <body>

    <article>
EOF1

	echo "<h1>Content of $1</h1><ol>"	
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	for file in $(ls -a $1)
	do
		if [ -d "${1}${file}" ] 
		then echo "<li class=\"directory\"><a href=\"${file}/\">${file}</a></li>"
		else echo "<li class=\"file\"><a href=\"${file}\">${file}</a></li>"
		fi
	done
	IFS=$SAVEIFS
	echo "</ol></article><footer>"
	echo "<p>brought to you by <a href=\"https://github.com/araex/BASHare\">bashare</a></p>"
	echo "</footer></body></html>"

}

# generate http error page
# $1 http response type
# $2 [optional] mime-type
send_response(){
	send_header $1 ${2-"text/html"}
	echo "<html><head><title>${HTTP_RESPONSE[$1]}</title></head>"
	echo "<body><h1>$1</h1><h2>HTTP ERROR $1: ${HTTP_RESPONSE[$1]}</h2>"
	echo "</body></html>"
}

if [ $BSHR_SOCAT_CALL ] 
then
	unset BSHR_SOCAT_CALL
	__read
else
__init $@
fi
