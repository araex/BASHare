#! /bin/bash

__read(){
	REQ=`while read L && [ " " "<" "$L" ] ; do echo "$L" ; done`
	REQMETHOD=($(echo "$REQ" | grep "GET"))
	
	case ${REQMETHOD[0]} in
		GET)
			FILE=${REQMETHOD[1]}
			if   [[ $FILE == */ ]] #is dir 
			then     send_header 200
				 send_directory_index "${PWD}${FILE}";
			elif [ -f "${FILE}" ]
			then send_response 500
			else send_response 404
			fi
			;;
		*)
			send_response 418
			;;
	esac
}

# send http header with response code $1
send_header(){
	echo "HTTP/1.1 $1 ${HTTP_RESPONSE[$1]}"
	echo "Server: bashare.sh"
	echo "Content-Type: text/html; charset=UTF-8"
	echo "Connection: close"
	echo -en "\r\n\r\n"
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

# send directory index
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
	for file in $(ls -a $1)
	do
		if [ -d "${1}${file}" ] 
		then echo "<li class=\"directory\"><a href=\"${file}/\">${file}</a></li>"
		else echo "<li class=\"file\"><a href=\"${file}\">${file}</a></li>"
		fi
	done
	echo "</ol></article><footer>"
	echo "<p>brought to you by <a href=\"https://github.com/araex/BASHare\">bashare</a></p>"
	echo "</footer></body></html>"

}

send_response(){
	send_header $1
	echo "<html><head><title>${HTTP_RESPONSE[$1]}</title></head>"
	echo "<body><h1>$1</h1><h2>HTTP ERROR $1: ${HTTP_RESPONSE[$1]}</h2>"
	echo "</body></html>"
}

# main loop
main(){
	[ $UID == 0 ] && echo "You shouldn\'t run this script as root..."
	PORT=${1-8000}
	IOPIPE=/tmp/basharepipe
	[ -p $IOPIPE ] || mkfifo $IOPIPE
	echo "Directory '${PWD}' is now available on port $PORT"
	while true
	do
		nc -l "$PORT" 0<backpipe | (__read) 1>backpipe
	done
}

main "$@"
