#!/bin/bash
cd ~/openaps-dev
#git fetch --all && git reset --hard origin/master && git pull
#git pull
stat -c %y clock.json | cut -c 1-19
cat clock.json | sed 's/"//g' | sed 's/T/ /'
echo

# aktuelle Temp lesen nach änderung vom Prozess
openaps report invoke currenttemp.json

nodejs /home/pi/openaps-dev/pebble.js  glucose.json clock.json iob.json current_basal_profile.json currenttemp.json isf.json requestedtemp.json profile.json > www/openaps.json



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

