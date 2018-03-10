#!/bin/bash


######### DEPENDANCIES #########
################################
##                            ##
##            jq              ##
##           paste            ##
##                            ##
################################
################################

############ USAGE #############
################################
##                            ##
##  To download:              ##
##     script.sh <url>        ##
##                            ##
##  To download all threads   ##
##  that match regrex:        ##
##     script.sh -l\          ##
##     <board> <regrex>       ##
##                            ##
##  To clean:                 ##
##     script.sh <url> clean  ##
##                            ##
################################
################################

## Set default values
wgetargs=''
quiet=false

## Download all threads with subject or comment maching regular expression (PCRE, incasesensetive)
lurkmode=false

## Remove broken files
cleanmode=false

## Refresh time
mins=1

## Path to 4bash
SCRIPT="$0"

## Loop status
loop=true

## timestamp of the last reply
last_timestamp=0

## Parse commandline arguments
while [[ $# -gt 0 ]]; do
arg="$1"

case $arg in
    -q|--quiet)
	wgetargs="$wgetargs -q"
	quiet=true
	;;
    -t|--refresh-time)
	shift
	mins="$1"
	;;
    -l|--lurk)
	lurkmode=true
	shift
	board="$1"
	regrex="$2"
	shift
	;;
    -1|--once|once)
	loop=false
	;;
    -c|--clean|clean)
	cleanmode=true
	;;
    *)
	url="$1"
	;; 
esac
shift

done

## If user selected 'lurk mode'
if $lurkmode ; then
    args=''
    [[ ! loop ]] && args='--once'
    #TODO doc
    for no in $(wget --quiet -O - "a.4cdn.org/$board/catalog.json" |\
		     jq --arg regrex "$regrex" '.[] | .threads | .[] | 
		     	      	     if (.com + "\n" + .sub | test( $regrex;"i" )) then .no  else empty end? ')
    do "$SCRIPT" --quiet $args --refresh-time "$mins" "https://boards.4chan.org/$board/thread/$no" &
    done

    exit

fi


## Sanitize URL
url=$(echo $url | sed -r 's!^https?://!!' | sed 's/#.*//')
## Get the board name
board=$(echo $url | awk -F"/" '{print $2}')
## Get the thread number
thread=$(echo $url | awk -F"/" '{print $4}')


## Dir maker ##
mkdir -p ./$board
mkdir -p ./$board/$thread

## Dir location
dir=./$board/$thread

## Refresh time in seconds
secs=$(($mins * 60))


if $cleanmode ; then
## If clean, check for file health
#   I know the method is cheesy, but it works
#   TODO Optimize these loops into one?
    echo Checking for Broken JPGs
    for image in $dir/*.jpg; do
	eof=$(xxd -s -0x04 $image | awk '{print $3}')
	if [[ ! "$eof" = "ffd9" ]]; then
	    echo Removing $image
	    rm $image
	fi
    done

    echo Checking for Broken PNGs
    for image in $dir/*.png; do
	eof=$(xxd -s -0x04 $image | awk '{print $2 $3}')
	if [[ ! "$eof" = "ae426082" ]]; then
	    echo Removing $image
	    rm $image
	fi
    done

    echo Checking for Broken GIFs
    for image in $dir/*.gif; do
	eof=$(xxd -s -0x04 $image | awk '{print $3}')
	if [[ ! "$eof" = "003b" ]]; then
	    echo Removing $image
	    rm $image
	fi
    done

    echo Checking for Broken WEBMs
    for image in $dir/*.webm; do
	eof=$(xxd -s -0x04 $image | awk '{print $3}')
	if [[ ! "$eof" = "8104" ]]; then
	    echo Removing $image
	    rm $image
	fi
    done

    # I set it to exit the script after cleaning
    # But it would be nice too if you can make it
    # Run the script afterwards, but whatever
    exit
fi

echo "Downloading thread $board/$thread"

## Loop forever until ^C or exit
while true; do

    [[ $quiet ]] || echo Updating file...

    ## This will get the JSON from a.4cdn.org
    #   and output it to a variable.
    #   If file does not exist, exit
    #
    #   NOTE that it will download this every time and replace
    #     the one you have regardless if it's old or the same
    json="$(wget -O - -q "https://a.4cdn.org/$board/thread/$thread.json")" || { echo "Thread $board/$thread deleted or does not exist."; exit; }

    ## Get last replies timestamp
    timestamp="$(echo "$json" | jq '.posts | .[-1] | .time')"

    ## If there is new reply
    if [[ timestamp -gt last_timestamp ]] ; then

	## Safe JSON
	echo "$json" > $dir/$thread.json
       
	## This will interpret the json file and create incremental list of files.
	#   In first line jq compares timestamp of the reply with saved timestamp,
	#   if it finds new one, in second line it adds new record to list. First list filed is `tim`+`ext` and second is `md5`.
	#   In third line replies without files are rejected.
	#   Then it saves list to a variable so wget can download new files
	list="$(echo "$json"\
	    	    | jq  --arg timestamp "$last_timestamp" -r '.posts | .[] | if ( .time >= ($timestamp | tonumber ) )
    		      then ( .tim | tostring ) + .ext?, .md5 else empty end' \
	    	    | sed '/null/d' \
	    	    | paste -s -d' \n' )"
	    #| tr -d ' ' \ #TMP
	    #| sed -e "s/^/https:\/\/i.4cdn.org\/$board\//" \
		#> $dir/$thread.files

	## This loop will download files from the list with wget
	#   using the dot style progress bar to make it pretty.

	while read line ; do
	    file="${line% *}" # Extract filename form first field with parameter expansion
	    wget ${wgetargs} -nc -P $dir/ -c --progress=dot "https://i.4cdn.org/$board/$file"
	done<<<"$list"
	
	## Exit if requested to run once.
	if ! $loop ; then
	    exit
	fi

	## Save timestamp
	last_timestamp=$timestamp
    fi

    ## This while loop will redo the whole thing after the given amount
    #   of refresh seconds
    #
    #  I initially was going to use `tput` since I just found out about it
    #   but this does the job anyway
    sec=10 #$secs #TMP
    while [ $sec -gt 0 ]; do
	if ! $quiet ; then
            printf "Download complete. Refreshing in:  %02d\033[K\r" $sec
	fi
	sleep 1
        : $((sec--))
    done

done
