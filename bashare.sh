#! /bin/bash

__read(){
	#while read line
	#do
	#done
	send_header 200
	send_directory_index $PWD
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
	[500]="Internal Server Error"
)

# send directory index
send_directory_index(){
	echo "<html><head><title>Index of $1</title></head>"
	echo "<body>"
	echo "<h1>Index of /$1</h1><hr><pre><a href="../">../</a>"
	for file in $(ls $1)
	do
		echo "<a href=\"${file}/\">$file</a>"
	done
	echo "</pre><hr></body></html>"
}

# main loop
main(){
	[ $UID == 0 ] && echo "You shouldn\'t run this script as root..."
	PORT=${1-8000}
	rm backpipe
	echo "Directory '${PWD}' is now available on port $PORT"
	while [ $? -eq 0 ]
	do
		mkfifo backpipe
		nc -l "$PORT" 0<backpipe | __read 1>backpipe
		rm backpipe
	done
	rm backpipe
}

main "$@"