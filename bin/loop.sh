#!/bin/bash
# Olli@schumis-net.de
# loop Script für OpenAPS
# 19.08.2015  V 0.01


# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

model=512

LOGFILE="/var/log/openaps/openaps.log"

logmsg () { 
  echo "$(date) : $@" >> $LOGFILE 
  echo "$(date) : $@" 
}

die() { 
  echo \{\"content\":\"Fehler !! : $(date) : $@ \",\"refresh_frequency\":5\ ,\"vibrate\":2} >www/openaps.json
  logmsg "$@"
  

IP_address=cgmcloud.de
username="pebbleupload"
PASSWD=gVh3e6_7
USER=pebbleupload
FILE='www/openaps.json openaps.json'

ftp -n $IP_address <<END_SCRIPT
quote USER $USER
quote PASS $PASSWD
put $FILE
bye
END_SCRIPT

  exit; 
}

function finish {
    rm /tmp/openaps.lock 2>/dev/null
}
trap finish EXIT

# define functions for everything we'll be doing

# get glucose data, either from attached CGM or from Share
getglucose() {
    echo "Querying CGM"
    ( ( openaps report invoke glucose.json.new || openaps report invoke glucose.json.new ) && grep -v '"glucose": 5' glucose.json.new | grep glucose ) || share2-bridge file glucose.json.new
    grep glucose glucose.json.new && cp glucose.json.new glucose.json && git commit -m"glucose.json has glucose data: committing" glucose.json
}

# get pump status (suspended, etc.)
getpumpstatus() {
    echo "Checking pump status"
    openaps status
    grep -q status status.json.new && cp status.json.new status.json
}

# query pump, and update pump data files if successful
querypump() {
    openaps pumpquery || openaps pumpquery
    findclocknew && grep T clock.json.new && cp clock.json.new clock.json
    grep -q temp currenttemp.json.new && cp currenttemp.json.new currenttemp.json
    grep -q timestamp pumphistory.json.new && cp pumphistory.json.new pumphistory.json
    upload
}

# try to upload pumphistory data
upload() { findpumphistory && ~/bin/openaps-mongo.sh && touch /tmp/openaps.online; }

# if we haven't uploaded successfully in 10m, use offline mode (if no temp running, set current basal as temp to show the loop is working)
suggest() {
    openaps suggest
    find /tmp/openaps.online -mmin -10 | egrep -q '.*' && cp requestedtemp.online.json requestedtemp.json || cp requestedtemp.offline.json requestedtemp.json
}

# get updated pump settings (basal schedules, targets, ISF, etc.)
getpumpsettings() { ~/openaps-js/bin/pumpsettings.sh; }

# functions for making sure we have up-to-date data before proceeding
findclock() { find clock.json -mmin 10 | egrep -q '.*'; }
findclocknew() { find clock.json.new -mmin 10 | egrep -q '.*'; }
findglucose() { find glucose.json -mmin 10 ; }
findpumphistory() { find pumphistory.json -mmin 10 | egrep -q '.*'; }
findrequestedtemp() { find requestedtemp.json -mmin 10 | egrep -q '.*'; }

# write out current status to pebble.json
pebble() { findclock && findglucose && findpumphistory && findrequestedtemp && ~/openaps-js/bin/pebble.sh; }


##########################################################################################################################################################################################################################
# Start Main
#
#
#
#


cd /home/pi/openaps-dev/

logmsg "########################################     Start Openaps loop      ########################################"

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# remove any old stale lockfiles
find /tmp/openaps.lock -mmin +10 -exec rm {} \; 2>/dev/null > /dev/null

# only one process can talk to the pump at a time
ls /tmp/openaps.lock >/dev/null 2>/dev/null && die "OpenAPS already running: exiting" && exit

touch /tmp/openaps.lock

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# make sure decocare can talk to the Carelink USB stick
~/decocare/insert.sh 2>/dev/null >/dev/null
python -m decocare.stick $(python -m decocare.scan) >/dev/null && logmsg "decocare.scan OK" || (sudo shutdown -r now &&  die "decocare Scan NOK")  # sudo ~/openaps-js/bin/fix-dead-carelink.sh

# sometimes git gets stuck
find ~/openaps-dev/.git/index.lock -mmin +5 -exec rm {} \; 2>/dev/null > /dev/null
git status > /dev/null || ( mv ~/openaps-dev/.git /tmp/.git-`date +%s`; cd && openaps init openaps-dev && cd openaps-dev  )

# sometimes openaps.ini gets truncated
openaps report show > /dev/null || cp openaps.ini.bak openaps.ini

logmsg "Kurz schlafen da BZ wert aus Nightscout immer spaeter erst aktuell ist (dauer 70s)"

# sleep 70s

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "Alte json files loeschen"


rm profile.json > /dev/null 2>/dev/null
rm glucose.json > /dev/null 2>/dev/null
rm clock.json > /dev/null 2>/dev/null
rm currenttemp.json > /dev/null 2>/dev/null
rm pumphistory.json > /dev/null 2>/dev/null
rm iob.json > /dev/null 2>/dev/null
rm requestedtemp.json > /dev/null 2>/dev/null
rm enactedtemp.json > /dev/null 2>/dev/null


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# OpenAPS git neu initialisieren

rm -r -f .git
openaps init >/dev/null 2>/dev/null

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Parameter aus Pumpe alle 24h lesen oder nach reboot.

# loc
find /tmp/openaps_getpara.lock -mmin +1440 -exec rm {} \; 2>/dev/null > /dev/null

if ls /tmp/openaps_getpara.lock >/dev/null 2>/dev/null
  then 
	logmsg "Parameter aus der Pumpe nicht lesen  Datei -> /tmp/openaps_getpara.lock vorhanden"
  else 
	logmsg "Parameter aus der Pumpe lesen"
	# Ersteinmal alte json löschen
	rm carbratio.json > /dev/null
	rm isf.json > /dev/null
	rm current_basal_profile.json > /dev/null

	####################################################################################
	# Diese Zeilen nur wenn pumpe keine 512 oder 712 ist
	rm bgtargets.json > /dev/null
	rm pumpsettings.json > /dev/null
	
	openaps report invoke bgtargets.json || openaps report invoke bgtargets.json || die "(err) Konnte bgtargets nicht lesen !!! exit()"
	openaps report invoke pumpsettings.json  || openaps report invoke pumpsettings.json  || die "(err) Konnte pumpsettings nicht lesen !!! exit()"
	####################################################################################
	
	
	# carbratio lesen
	# device pump read_carb_ratios
	openaps report invoke carbratio.json || openaps report invoke carbratio.json || die "(err) Konnte carbratio nicht lesen !!! exit()"

	# device pump read_insulin_sensitivies
	openaps report invoke isf.json || openaps report invoke isf.json || die "(err) Konnte isf nicht lesen !!! exit()"

	# device pump read_basal_profile_std
	openaps report invoke current_basal_profile.json || openaps report invoke current_basal_profile.json || die "(err) Konnte current_basal_profile nicht lesen !!! exit()"

	# **********************   Werden von der 512 nicht unterstuetzt
	# device pump read_bg_targets
	# openaps report invoke read_bg_targets.json
	# device pump read_settings
	# openaps report invoke pumpsettings.json
	# **********************
	touch /tmp/openaps_getpara.lock
fi


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




## TODO Irgendwie das mit der Uhrzeit noch machen !!!
# clockset.sh




#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report clock.json"
# Uhr der Pumpe lesen
# device pump read_clock
openaps report invoke clock.json || openaps report invoke clock.json || die "(err) Keine Verbindung mit der Pumpe -> Konnte Clock nicht lesen !!! Fehler: Pumpe ausserhalb Reichweite oder Batterie der Pumpe zu schwach  exit()"

# uhr des PI auf den der Pumpe setzen
# ./clockset.sh

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report currenttemp.json"
# device pump read_temp_basal
openaps report invoke currenttemp.json || openaps report invoke currenttemp.json || die "(err) Keine Verbindung mit der Pumpe -> Konnte currenttemp nicht lesen !!! Fehler: Pumpe ausserhalb Reichweite ? exit()"
logmsg "report currenttemp.json Fertig->"
while read line; do logmsg $line ;done < currenttemp.json

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report pumphistory.json"
# device pump iter_pump
openaps report invoke pumphistory.json || openaps report invoke pumphistory.json || die "(err) Keine Verbindung mit der Pumpe -> Konnte pumphistorie nicht lesen !!! Fehler: Pumpe ausserhalb Reichweite ? exit()"

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report profile.json"
# device getprofile.js
# inputs pumpsettings.json bgtargets.json isf.json current_basal_profile.json carbratio.json
openaps report invoke profile.json || die "(err) Keine Verbindung mit der Pumpe -> Konnte profile nicht erzeugen !!! Fehler: Pumpe ausserhalb Reichweite ? exit()"
logmsg "report profile.json Ausgabe:"
while read line; do logmsg $line ;done < profile.json

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report iob.json" 
# device iob.js
# input: pumphistory.json profile.json clock.json
openaps report invoke iob.json || die "(err) Interner Fehler. Konnte iob nicht verarbeiten !!! exit()"

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "Daten von Dexcom alternativ von Nightscout lesen [report glucose.json]"
#openaps report invoke bgreading.json || openaps report invoke bgreading.json || ./get_nsbgreading.sh
./get_nsbgreading.sh

logmsg "glucose.json"
# while read line; do logmsg $line ;done < glucose.json

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report requestedtemp.json"
# device determinebasal.js (shell)
# input: iob.json currenttemp.json bgreading.json profile.json
openaps report invoke requestedtemp.json || die "(err) Interner Fehler. Konnte requested temp nicht erzeugen !!! exit()"

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "requestedtem.json Ausgabe:"
while read line; do logmsg $line ;done < requestedtemp.json

# device pump set_temp_basal  
# input: requestedtemp.json
# openaps report invoke enactedtemp.json

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "report enactedtemp.json"
# don't act on stale glucose data
# findglucose && grep -q glucose glucose.json || die "No recent glucose data"
findglucose || die "Keine aktuellen Blutzucker Daten (Ursachen. Keine Internet Verbindung, Probleme mit dem Sensor ?)"
# execute/enact the requested temp
grep -q rate requestedtemp.json && ( openaps report invoke enactedtemp.json || openaps report invoke enactedtemp.json ) && tail enactedtemp.json

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "enactedtemp.json Ausgabe:"
while read line; do logmsg $line ;done < enactedtemp.json 2>/dev/null


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logmsg "send to pebble"
./pebble.sh
while read line; do logmsg $line ;done < www/openaps.json 2>/dev/null


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
if ls enactedtemp.json >/dev/null 2>/dev/null
  then
	logmsg "send to Nightscout/Azure "
	nodejs /home/pi/openaps-dev/sendtempbasal-ns.js  iob.json enactedtemp.json glucose.json profile.json requestedtemp.json > www/ns-openaps.json || nodejs /home/pi/openaps-dev/sendtempbasal-ns.js  iob.json enactedtemp.json glucose.json profile.json requestedtemp.json > www/ns-openaps.json || logmsg "Hmm irgendwie gibt es ein prob."
	# nodejs /home/pi/openaps-dev/sendtempbasal-azure.js  iob.json enactedtemp.json glucose.json  > www/azure-openaps.json

	
	while read line; do logmsg $line ;done < www/ns-openaps.json 2>/dev/null
  else
	logmsg "No Data for Nightscout/Azure"
fi



logmsg "#### END ####"



