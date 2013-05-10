#! /bin/bash
# BASHare is a utility that shares the currently open directory on a built in webserver
# dependencies: 'socat' or 'netcat'* 
# *netcat does not offer multiple simultanious connections

__init(){	
	# exit on CTRL+C
	trap exit 1 2 3 6

	# check if started with root privileges
	[ $UID == 0 ] && echo "You shouldn\'t run this script with root privileges..."

	# check if socat / netcat is installed
	command -v socat >/dev/null 2>&1 && socat="true"
	command -v netcat >/dev/null 2>&1 && netcat="true"

	# MIME-types that can be compressed
	ENC_TYPES="text/html text/css text/plain text/xml application/x-javascript application/x-httpd-phpi"
	__parse_Args $@

	# prefer usage of socat
	if [ $socat ]; then
		echo "Using socat. Directory '${PWD}' is now available on port ${BSHR_PORT}"
		# get currently active dir (might differ from $PWD!!"
		DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
		# set var to identify recursive script call
		export BSHR_SOCAT_CALL="true"
		# let socat execute the script
		socat TCP4-LISTEN:${BSHR_PORT},fork EXEC:"${DIR}/bashare.sh"
		echo "Socat terminated. Goodbye."
	elif [ $netcat ]; then
		#TEMPORARILY REMOVED#NCGNU=`nc --version | head -n 1 | grep GNU`; 
		#####################[ "$NCGNU" ] && echo "netcat-gnu is currently not supported. Please install either socat, openbsd-netcat or netcat-traditional. Terminating." && exit 1

		# prepare bidrectional pipe for communication between script and netcat
		IOPIPE=/tmp/basharepipe
		[ -p $IOPIPE ] || mkfifo $IOPIPE
		echo "Using netcat. Directory '${PWD}' is now available on port ${BSHR_PORT}"
		# run in loop for compatiblity with OpenBSD-netcat which doesn't seem to implement -k correctly. gnu-netcat lacks the -k option.
		while true
		do
			nc "-klp" "${BSHR_PORT}" 0<$IOPIPE | (__read) 1>$IOPIPE
		done
		echo "Netcat terminated. Goodbye."
	else
		echo "Couldn't locate netcat or socat, aborting."
		exit 1
	fi	
}	

# parse command line arguments, export them for socat use
__parse_Args(){
	export BSHR_PORT=8000
	while getopts "p:hrnv" opt; do
  		case $opt in
    			p)  BSHR_PORT=$OPTARG;;
			h)  __showHelp $0;;
			r)  echo "NOT IMPLEMENTED YET. Show only current directory, no subdirectories.";;
			n)  socat="";;
			v)  export BSHR_VERBOSE="true";;
    			\?)  __showHelp $0;;
  		esac
	done
}

# called when -h is passed
__showHelp(){
	echo "Usage: `basename $1`: [-p port]"
	echo "  -p: port to use"
	echo "  -r: only serve current directory, no subdircetories"
	echo "  -n: force use of netcat even if socat is installed"
	echo "  -v: enable verbose mode"
	echo "  -h: show this help"
	exit 1
}

decode_url() {
 	printf -v decoded_url '%b' "${1//%/\\x}"
	echo "$decoded_url"
}

# HTTP request interpreter
__read(){
	# get first line of http request: METHOD PATH HTTPVERSION
	read request
	# transform to array. request[0]=METHOD, request[1]=PATH, request[2]=HTTPVERSION
	request=($request)
	# get path and all arguments
	save=$IFS
	IFS='?' read -a path <<< "${request[1]}"
	IFS=$save

	[ $BSHR_VERBOSE ] && echo "${request[*]}">&2
	# get rest of request header for additional options
	while read line && [ " " "<" "$line" ]; do 
		header+="${line}" 
	done
	# check if client supports http compression with gzip
	[[ "$header" == *gzip* ]] && encgzip="true"

	# only GET is supported at the moment
	case ${request[0]} in
		GET)
			# build fully qualified directory name
			url="${PWD}${path[0]}"
			# revert encoded url
			url=`decode_url $url`
			# if requested url is tarball of dir
			if [[ ${path[1]} == getTarGz ]]; then
				send_header 200 "application/x-gzip"
				cd "${url%/*}"
				tar -cO | gzip -cf
			# if requested url is a directory, send directory listing
			elif [ -d "$url" ]; then
				if [[ $url == *.ssh* ]]; then
					send_response 403
				elif [ $encgzip ]; then 
					send_header 200 "text/html"
					send_directory_index "${url}" "${path[0]}" | gzip -cf
				else 
					send_header 200 "text/html"
					send_directory_index "${url}" "${path[0]}"
				fi
			# if requested url is a file, send file
			elif [ -f "${url}" ]; then 
				# get mimetype
				mimetype=$(file --mime-type "${url}" | sed 's#.*:\ ##')
				# if mimetype is not encodable, unset ENGZIP
				[[ "$ENC_TYPES" == *${mimetype}* ]] || ENGZIP=""
				send_header 200 ${mimetype} $(stat -c%s "${url}")
				if [ $encgzip ]; then 
					gzip -c "${url}"
				else 
					cat "${url}"
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
	[ $encgzip ] && echo "Content-Encoding: gzip"
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

	dir=$1
	reldir=$2

# HTML / CSS
cat <<'EOF1'
<html>
  <head>
    <meta charset="utf-8"/>
    <style>
	@import url(http://fonts.googleapis.com/css?family=Abel);
	body, html { background: #222; margin: 0; }
	html { font: 14px/1.4 'Abel', sans-serif; color: #ddd; font-weight: 300; }
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

	echo "<h2>Content of `decode_url $reldir`</h2>"	
	echo "<div class=\"list\">"
	echo "<table summary=\"Directory Listing\" cellpadding=\"0\" cellspacing=\"0\">"
	echo "<thead><tr><th class="n">Name</th><th class="m">Last Modified</th><th class="s">Size</th><th class="t">MIME-Type</th><th class="d">Download as archive</th></tr></thead>"
	echo "<tbody>"
	saveifs=$IFS
	IFS=$(echo -en "\n\b")
	#echo "<tr><td class=\"n\"><a href=\"..\">../</a></td><td class=\"m\">-</td><td class=\"s\">-</td><td class=\"t\">-</td></tr>"
	# HTML for directory listing
	for entry in $(ls -la $1); do
		IFS=$saveifs
		entry=($entry)
		file=$*
		size=`echo "${entry[4]}" | awk {'printf("%.2f kB", $1/1024)'}`
		date="${entry[6]} ${entry[5]} ${entry[7]}"
		file=""
		for (( i=8; i<=${#entry[@]}; i++ )); do 
			file="${file}${entry[i]} " 
		done
		file=$(echo "${file}" | sed 's/ *$//g') #remove tailing whitespace
		if [ -d "${dir}${file}" ] 
		then
			file="${file}/"
			size="-"
			mimetype="Directory"
			archive="<td class=\"d\"><a href =\"${file}${file%?}.tgz?getTarGz\">.tar</a></td>"
		else 
			mimetype=$(file --mime-type "${url}${file}" | sed 's#.*:\ ##')
			archive=""
		fi
		echo "<tr><td class=\"n\"><a href=\"${file}\">${file}</a></td><td class=\"m\">${date}</td><td class=\"s\">${size}</td><td class=\"t\">${mimetype}</td>${archive}</tr>"
	done

	echo "</tbody></table></div><div class="foot">powered by <a href=\"https://github.com/araex/BASHare\">bashare</a></div></body></html>"

}

# generate http error page
# $1 http response type
# $2 [optional] mime-type
send_response(){
	encgzip=""
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
