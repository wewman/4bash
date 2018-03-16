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

## Timestamp of the last reply
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
    [[ $loop == false ]] && args='--once'
    ## In 'lurk mode' 4bash scans whole board for threads that has subject or comment matching regular expression (incasesensitive, PCRE) provided by user
    for no in $(wget --quiet -O - "a.4cdn.org/$board/catalog.json"   |\
		     jq --arg regrex "$regrex" '.[] | .threads | .[] | 
		     	      	     if (.com + "\n" + .sub | test( $regrex;"i" )) then .no  else empty end? ')
    do
	sleep 1 # Wait 1 second (reqired by API rules)
	"$SCRIPT" --quiet $args --refresh-time "$mins" "https://boards.4chan.org/$board/thread/$no" &
    done

    sleep 1
    echo Done.
    
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
    #   TODO allow user to use path to JSON rather using link to thread.
    #   TODO doc

    result=0

    echo "Checking for broken files in $dir ..."
    
    [[ -r $dir/$thread.json && -f $dir/$thread.json ]] || { echo "Unable to read from $dir/$thread.json !"; exit 1; }
    jq . $dir/$thread.json > /dev/null || { echo "$dir/$thread.json is not valid JSON!"; exit 1; }

    if [ ! "$board" == 'f' ] ; then
	list="$(jq -r '.posts | .[] | .md5, ( .tim | tostring ) + .ext?' $dir/$thread.json \
		  | sed '/null/d' \
		  | paste -s -d' \n' )"
    else
	list="$(jq -r '.posts | .[] | .md5, .filename + .ext?' $dir/$thread.json \
		  | sed '/null/d' \
		  | paste -s -d' \n' )"
    fi
    
    while read line ; do
	valid_md5=`echo "${line%% *}" | base64 -d | xxd -p -l 16`
	filename="$dir/`basename "${line#* }"`"
	
	if [[ -f $filename ]] ; then
	    if [[ "$valid_md5  $filename" == `md5sum "$filename"` ]] ; then
		[[ $quiet == false ]] && echo "file $filename: OK"
	    else
		[[ $quiet == false ]] && echo "file $filename: BAD_CHECKSUM"
		result=1
		rm -v "$filename"
	    fi
	else
	    [[ $quiet == false ]] && echo "file $filename: MISSING"
	    result=1
	fi
    done<<<"$list"
    
    echo Done.
    # I set it to exit the script after cleaning
    # But it would be nice too if you can make it
    # Run the script afterwards, but whatever
    exit $result
fi

echo "Downloading thread $board/$thread"

## Loop forever until ^C or exit
while true; do

    [[ $quiet == false ]] && echo 'Updating data...'

    ## This will get the JSON from a.4cdn.org
    #   and output it to a variable.
    #   If file does not exist, exit

    json="$(wget -O - -q "https://a.4cdn.org/$board/thread/$thread.json")" || { echo "Thread $board/$thread deleted or does not exist."; exit; }

    ## Get last replies timestamp
    timestamp="$(echo "$json" | jq '.posts | .[-1] | .time')"

    ## If there is new reply...
    if [[ timestamp -gt last_timestamp ]] ; then

	## Safe JSON
	echo "$json" > "$dir/$thread.json"

	if [ ! "$board" == 'f' ] ; then
	    ## This will interpret the JSON file and create incremental list of files.
	    #   In first line jq compares timestamp of the reply with saved timestamp,
	    #   if it finds new one, in second line it adds new record to list. First list filed is `md5` (for future usage) and second is `tim`+`ext`.
	    #   In third line replies without files are rejected.
	    #   Then it saves list to a variable so wget can download new files
	    list="$(echo "$json"\
			| jq  --arg timestamp "$last_timestamp" -r '.posts | .[] | if ( .time >= ($timestamp | tonumber) )
			  then .md5, ( .tim | tostring ) + .ext? else empty end' \
			| sed '/null/d' \
			| paste -s -d' \n' )"
	else
	    # On /f/ link to filename is build of filename, not tim
	    list="$(echo "$json"\
			| jq  --arg timestamp "$last_timestamp" -r '.posts | .[] | if ( .time >= ($timestamp | tonumber) )
			  then .md5, (.filename | @uri) + .ext? else empty end' \
			| sed '/null/d' \
			| paste -s -d' \n' )"	    
	fi
	   

	## This loop will download files from the list with wget
	#   using the dot style progress bar to make it pretty.

	while read line ; do
	    file="${line#* }" # Extract filename from second field with parameter expansion
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
    sec=$secs
    [ $sec -gt 0 ] || sec=10 # If user sets refresh time to 0 wait 10 seconds to follow API rules. 
    while [ $sec -gt 0 ]; do
	if ! $quiet ; then
            printf "Download complete. Refreshing in:  %02d\033[K\r" $sec
	fi
	sleep 1
        : $((sec--))
    done
    [[ $quiet == false ]] && echo # Print newline

done
