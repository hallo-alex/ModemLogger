#!/bin/bash



TMP_DIR=`mktemp -d`

#default values

#you can put a ModemLogger.cfg in /etc local directory or in ~/.ModemLogger.cfg
ADDRESS=192.168.100.1
OUTDIR=./out
DBDIR=./db

USERNAME=
PASSWORD=

CHANNELSTART=1
CHANNELEND=8


CHANNELCOLORS=(	'#000000' '#888888' 'FF0000' '#00FF00' '0000FF' '888888' 'FFFF00' '00FFFF' );


WGETUSERAGENT=--user-agent\=Mozilla/5.0
#for debuggin purposes
WGETQUIET=-q

debugPrint(){
	if [ -n "$DEBUGMESSAGES" ]; then
		echo $*
	fi
}

debugPrint "looking for global config file..."
if [ -r /etc/ModemLogger.cfg ]; then
  debugPrint "Reading global config"
  . /etc/ModemLogger.cfg
fi

debugPrint "looking for user config file..."
if [ -r ~/.ModemLogger.cfg ]; then
  debugPrint "Reading user config"
  . ~/.ModemLogger.cfg
fi

debugPrint "looking for local config file..."
if [ -r ModemLogger.cfg ]; then
  debugPrint "Reading local config"
  . ModemLogger.cfg
fi

debugPrint "Config Values:"
debugPrint "ADDRESS=$ADDRESS"
debugPrint "USERNAME=$USERNAME"
debugPrint "PASSWORD=$PASSWORD"
debugPrint "TMP_DIR=$TMP_DIR"



WGET_COOKIESETTINGS="--save-cookies $TMP_DIR/cookies.txt --keep-session-cookies --load-cookies $TMP_DIR/cookies.txt"




#extracts data from status.html and logs
extractDataAndLog() {

	#extract Levels
	debugPrint "Extracting Levels"
	levelstring=$(cat $TMP_DIR/status.html |grep '<!-- Downstream Channel Information Start -->' -A100 | grep  '<!-- Downstream Channel Information End -->' -B100  | grep   'dw(vdbmv);' | grep -o  '\-*[0-9]\+\.[0-9]' | xargs -L13 -d'\n' | sed -e 's/ /:/g')
	debugPrint "Levelstring=$levelstring"

	debugPrint "Extracting Signal/Noise Ratio"
	snrstring=$(cat $TMP_DIR/status.html |grep '<!-- Downstream Channel Information Start -->' -A100 | grep  '<!-- Downstream Channel Information End -->' -B100  | grep   'dw(vdb);' | grep -o  '\-*[0-9]\+\.[0-9]' | xargs -L13 -d'\n' | sed -e 's/ /:/g')
	debugPrint " SNRstring=$snrstring"

	#Log Data
	debugPrint "Logging Data"
	rrdtool update $DBDIR/snr.rrd N:$snrstring
	rrdtool update $DBDIR/level.rrd N:$levelstring
}

#creates database files
init_db() {
	#timestamp
	NOW=`date +%s`
	#debug
	#echo NOW=$NOW

	CHSTRING=""
	for i in `seq $CHANNELSTART $CHANNELEND`;
		do
			#DataSource ChX is a Gauge from -100 to +100 with 300wtf?
			#TODO: Figure out how the databaselayout could be optimized
			CHSTRING+="DS:Ch${i}:GAUGE:300:-100:100 "
		done
	debugPrint "create SNR db starting $NOW"

	#TODO: Figure out what magic the RRA:... line does
	rrdtool create $DBDIR/snr.rrd --start $NOW \
		$CHSTRING \
		RRA:LAST:0.5:1:1200

debugPrint "create level db starting $NOW"
	rrdtool create $DBDIR/level.rrd --start $NOW \
	$CHSTRING \
	RRA:LAST:0.5:1:1200
}

#makes pngs out of logged data
#TODO:  give times as parameters
graph() {
	debugPrint "Generating Graphs"
	CHSTRING=""
	for i in `seq $CHANNELSTART $CHANNELEND`;
		do
			CHSTRING+="DEF:Ch${i}a=$DBDIR/snr.rrd:Ch$i:LAST LINE1:Ch${i}a${CHANNELCOLORS[(($i-$CHANNELSTART))]}:\"Ch$i\" "
    done
	rrdtool graph $OUTDIR/snr$1.png -a PNG --end now --start end-$1 --width 800 \
		$CHSTRING > /dev/null

	CHSTRING=""
	for i in `seq $CHANNELSTART $CHANNELEND`;
		do
			CHSTRING+="DEF:Ch${i}a=$DBDIR/level.rrd:Ch$i:LAST LINE1:Ch${i}a${CHANNELCOLORS[(($i-$CHANNELSTART))]}:\"Ch$i\" "
    done
	rrdtool graph $OUTDIR/level$1.png -a PNG --end now --start end-$1 --width 800 \
		$CHSTRING > /dev/null
}

#retreives the Log-Page, needs cookies.txt from getStatusWithLogin
getErrorLog() {
	debugPrint "fetching Errorlog"
	wget $WGETUSERAGENT $WGETQUIET $WGET_COOKIESETTINGS http://$ADDRESS/Docsis_log.asp -O $TMP_DIR/log.html
	#TODO: Test for Error
	debugPrint "Logging Out"
	wget $WGETUSERAGENT $WGETQUIET $WGET_COOKIESETTINGS http://192.168.100.1/logout.asp -O /dev/null
	#TODO: Test for Error
}


getStatus(){
	debugPrint "fetching Status"
	wget $WGETUSERAGENT $WGETQUIET http://$ADDRESS/Docsis_system.asp -O $TMP_DIR/status.html
	#TODO: Test for Error
}

getStatusWithLogin(){
	#get the status and store cookies
  debugPrint "fetching Status with Login"
	wget $WGETUSERAGENT $WGETQUIET $WGET_COOKIESETTINGS --post-data "username_login=$USERNAME&password_login=$PASSWORD" http://$ADDRESS/goform/Docsis_system -O $TMP_DIR/status.html
}

case $1 in
	getStatus)
		getStatus
		extractDataAndLog
		;;
	init)
		mkdir $OUTDIR
		mkdir $DBDIR
		init_db
		;;
	getErrors)
		getStatusWithLogin
		#we have new data - we can log them
		extractDataAndLog
		getErrorLog
		#TODO: cool, we've got the log - now what to do with it?
		;;
	graph)
		graph 1h
		graph 24h
		graph 31d
		;;
	*)
		echo "Usage: $0 {getStatus|getErrors|init|graph}"
		exit 2
		;;
esac

debugPrint "Removing $TMP_DIR"
rm -rf $TMP_DIR
debugPrint "The End"
