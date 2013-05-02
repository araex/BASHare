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
		NCGNU=`nc --version | head -n 1 | grep GNU`; 
		[ "$NCGNU" ] && echo "netcat-gnu is currently not supported. Please install either socat, openbsd-netcat or netcat-traditional. Terminating." && exit 1
		IOPIPE=/tmp/basharepipe
		[ -p $IOPIPE ] || mkfifo $IOPIPE
		echo "Using netcat. Directory '${PWD}' is now available on port ${BSHR_PORT}"
		while true
		do
			nc -klp "${BSHR_PORT}" 0<$IOPIPE | (__read) 1>$IOPIPE
		done
	else
		echo "Couldn't locate netcat or socat, aborting."
		exit 1
	fi	
}	

# parse command line arguments, export them for socat use
__parse_Args(){
	export BSHR_PORT=8000
	while getopts "p:hrn" opt; do
  		case $opt in
    			p)  BSHR_PORT=$OPTARG;;
			h)  __showHelp $0;;
			r)  echo "NOT IMPLEMENTED YET. Show only current directory, no subdirectories.";;
			n)  SOCAT="";;
    			\?)  __showHelp $0;;
  		esac
	done
}

__showHelp(){
	echo "Usage: `basename $1`: [-p port]"
	echo "  -p: port to use"
	echo "  -r: only serve current directory, no subdircetories"
	echo "  -n: force use of netcat even if socat is installed"
	echo "  -h: show this help"
	exit 1
}

# HTTP request interpreter
__read(){
	REQ=""
	while read line && [ " " "<" "$line" ]; do 
		REQ=${REQ}${line} 
	done
	REQMETHOD=($(echo "$REQ" | grep "HTTP"))
	[[ "$REQ" == *gzip* ]] && ENCGZIP="true"

	case ${REQMETHOD[0]} in
		GET)
			URL=${PWD}${REQMETHOD[1]}
			URL=${URL//'%20'/ }
			if   [[ $URL == */ ]] #is dir 
			then
				if [[ $URL == *.ssh* ]] 
				then
					send_response 403
				elif [ $ENCGZIP ]
				then 
					send_header 200 "text/html"
					send_directory_index "${URL}" "${REQMETHOD[1]}" | gzip -cf
				else 
					send_header 200 "text/html"
					send_directory_index "${URL}" "${REQMETHOD[1]}"
				fi
			elif [ -f "${URL}" ]
			then 
				MIMETYPE=$(file --mime-type "${URL}" | sed 's#.*:\ ##')
				VIABLETYPES="text/html text/css text/plain text/xml application/x-javascript application/x-httpd-phpi"
				[[ "$VIABLETYPES" == *${MIMETYPE}* ]] || ENGZIP=""
				send_header 200 ${MIMETYPE} $(stat -c%s "${URL}")
				if [ $ENCGZIP ]
				then gzip -c "${URL}"
				else cat "${URL}"
				fi
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
	[ $ENCGZIP ] && echo "Content-Encoding: gzip"
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

	DIR=$1
	RELDIR=$2

# HTML / CSS
cat <<'EOF1'
<html>
  <head>
    <meta charset="utf-8"/>
    <style>
    	@import url(http://fonts.googleapis.com/css?family=Raleway:200,400,600);
	body, html { background: #222; margin: 0; }
	html { font: 14px/1.4 Raleway, Helvetica, sans-serif; color: #ddd; font-weight: 400; }
	h2 { font-weight: 200; font-size: 32px; margin: 20px 35px; }
	div.list { background: #111; padding: 20px 35px; }
	div.foot { color: #777; margin-top: 15px; padding: 20px 35px; }

	td { padding: 0 20px; line-height: 21px; }
	tr:hover { background: black; }

	a { color: #6088BF; }
	a:visited { color: #BF85AC; }
	a:hover { color: #86B1BF; }
    </style>
    <title>Directory Index</title>
  </head>
  <body>

EOF1

	echo "<h2>Content of $RELDIR</h2>"	
	echo "<div class=\"list\">"
	echo "<table summary=\"Directory Listing\" cellpadding=\"0\" cellspacing=\"0\">"
	echo "<thead><tr><th class="n">Name</th><th class="m">Last Modified</th><th class="s">Size</th><th class="t">MIME-Type</th></tr></thead>"
	echo "<tbody>"
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	#echo "<tr><td class=\"n\"><a href=\"..\">../</a></td><td class=\"m\">-</td><td class=\"s\">-</td><td class=\"t\">-</td></tr>"
	for entry in $(ls -la $1)
	do
		IFS=$SAVEIFS
		entry=($entry)
		file=$*
		SIZE=`echo "${entry[4]}" | awk {'printf("%.2f kB", $1/1024)'}`
		DATE="${entry[6]} ${entry[5]} ${entry[7]}"
		file=""
		for (( i=8; i<=${#entry[@]}; i++ )); do 
			file="${file}${entry[i]} " 
		done
		file=$(echo "${file}" | sed 's/ *$//g') #remove tailing whitespace
		if [ -d "${DIR}${file}" ] 
		then
			file="${file}/"
			SIZE="-"
			MIMETYPE="Directory"
		else 
			MIMETYPE=$(file --mime-type "${URL}${file}" | sed 's#.*:\ ##')
		fi
		echo "<tr><td class=\"n\"><a href=\"${file}\">${file}</a></td><td class=\"m\">${DATE}</td><td class=\"s\">${SIZE}</td><td class=\"t\">${MIMETYPE}</td></tr>"
	done

	echo "</tbody></table></div><div class="foot">powered by <a href=\"https://github.com/araex/BASHare\">bashare</a></div></body></html>"

}

# generate http error page
# $1 http response type
# $2 [optional] mime-type
send_response(){
	ENCGZIP=""
	send_header $1 ${2-"text/html"}
	echo "<html><head><title>$1 : ${HTTP_RESPONSE[$1]}</title></head>"
	echo "<body><h1>$1: ${HTTP_RESPONSE[$1]}</h1>"
	echo "</body></html>"
}

if [ $BSHR_SOCAT_CALL ] 
then
	unset BSHR_SOCAT_CALL
	__read
else
__init $@
fi
