#!/bin/bash


######### DEPENDANCIES #########
################################
##                            ##
##           jq               ##
##           curl             ##
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


## Parse commandline arguments
while [[ $# -gt 0 ]]; do
arg="$1"

case $arg in
    -q|--quiet)
	wgetargs="$wgetargs -q"
	quiet=true
	shift
	;;
    -t|--refresh-time)
	shift
	mins="$1"
	shift
	;;
    -l|--lurk)
	lurkmode=true
	shift
	board="$1"
	regrex="$2"
	shift
	shift
	;;
    -1|--once|once)
	loop=false
	shift
	;;
    -c|--clean|clean)
	cleanmode=true
	shift
	;;
    *)
	url="$1"
	shift
	;; 
esac
done

if $lurkmode ; then
    args=''
    [[ ! loop ]] && args='--once' 
    for no in $(curl "a.4cdn.org/$board/catalog.json" -s |\
		     jq --arg regrex "$regrex" '.[] | .threads | .[] | if (.com + "\n" + .sub | test( $regrex;"i" )) then .no  else empty end? ')
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
    #   output it to a file quietly to save space
    #   if file does not exist, exit
    #
    #   NOTE that it will download this every time and replace
    #     the one you have regardless if it's old or the same
    wget -N https://a.4cdn.org/$board/thread/$thread.json -O $dir/$thread.json --quiet || { echo "Thread $board/$thread deleted or does not exist."; exit; } 

    ## This will interpret the json file and get only the `tim` and `ext`
    #   Then save it to a file so wget can use `-i` to download everything
    cat $dir/$thread.json \
        | jq -r '.posts | .[] | .tim?, .ext?' \
        | sed '/null/d' \
        | paste -s -d' \n' \
        | tr -d ' ' \
        | sed -e "s/^/https:\/\/i.4cdn.org\/$board\//" \
        > $dir/$thread.files

    ## This wget line will download the files from the file using -i
    #   And using the dot style progress bar to make it pretty.
    #
    #  Although, I initially want it so it won't show the messages
    #   when the files already exist, but  ... 2>&1 /dev/null
    #   will just remove the whole wget output text
    #  TODO Make it so it does not output any messages when
    #   the files exist.
    wget ${wgetargs} -nc -P $dir/ -c -i $dir/$thread.files --progress=dot

    ## Exit if requested to run once.
    if ! $loop ; then
        exit
    fi

    ## This while loop will redo the whole thing after the given amount
    #   of refresh seconds
    #
    #  I initially was going to use `tput` since I just found out about it
    #   but this does the job anyway
    sec=$secs
    while [ $sec -gt 0 ]; do
	if ! $quiet ; then
            printf "Download complete. Refreshing in:  %02d\033[K\r" $sec
	fi
	sleep 1
        : $((sec--))
    done

done
