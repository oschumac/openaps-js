#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

die() { echo "$@" ; exit 1; }

# remove any old stale lockfiles
find /tmp/openaps.lock -mmin +10 -exec rm {} \; 2>/dev/null > /dev/null

# only one process can talk to the pump at a time
ls /tmp/openaps.lock >/dev/null 2>/dev/null && die "OpenAPS already running: exiting" && exit

echo "No lockfile: continuing"
touch /tmp/openaps.lock

# make sure decocare can talk to the Carelink USB stick
~/decocare/insert.sh 2>/dev/null >/dev/null
python -m decocare.stick $(python -m decocare.scan) >/dev/null && echo "decocare.scan OK" || sudo ~/openaps-js/bin/fix-dead-carelink.sh

# sometimes git gets stuck
find ~/openaps-dev/.git/index.lock -mmin +5 -exec rm {} \; 2>/dev/null > /dev/null
cd ~/openaps-dev && ( git status > /dev/null || ( mv ~/openaps-dev/.git /tmp/.git-`date +%s`; cd && openaps init openaps-dev && cd openaps-dev ) )
# sometimes openaps.ini gets truncated
openaps report show > /dev/null || cp openaps.ini.bak openaps.ini

function finish {
    rm /tmp/openaps.lock
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
findclock() { find clock.json -mmin -10 | egrep -q '.*'; }
findclocknew() { find clock.json.new -mmin -10 | egrep -q '.*'; }
findglucose() { find glucose.json -mmin -10 | egrep -q '.*'; }
findpumphistory() { find pumphistory.json -mmin -10 | egrep -q '.*'; }
findrequestedtemp() { find requestedtemp.json -mmin -10 | egrep -q '.*'; }
# write out current status to pebble.json
pebble() { findclock && findglucose && findpumphistory && findrequestedtemp && ~/openaps-js/bin/pebble.sh; }


# main event loop

getglucose
head -15 glucose.json

numprocs=$(fuser -n file $(python -m decocare.scan) 2>&1 | wc -l)
if [[ $numprocs -gt 0 ]] ; then
  die "Carelink USB already in use or not available."
fi

getpumpstatus
echo "Querying pump" && querypump

upload

# get glucose again in case the pump queries took awhile
getglucose

# if we're offline, set the clock to the pump/CGM time
~/openaps-js/bin/clockset.sh

# dump out a "what we're about to try to do" report
suggest && pebble

tail clock.json
tail currenttemp.json

# make sure we're not using an old suggestion
rm requestedtemp.json*
# if we can't run suggest, it might be because our pumpsettings are missing or screwed up"
suggest || ( getpumpsettings && suggest ) || die "Can't calculate IOB or basal"
pebble
tail profile.json
tail iob.json
tail requestedtemp.json

# don't act on stale glucose data
findglucose && grep -q glucose glucose.json || die "No recent glucose data"
# execute/enact the requested temp
grep -q rate requestedtemp.json && ( openaps enact || openaps enact ) && tail enactedtemp.json

echo "Re-querying pump"
query pump

# unlock in case upload is really slow
rm /tmp/openaps.lock
pebble
upload

# if another instance didn't start while we were uploading, refresh pump settings
ls /tmp/openaps.lock >/dev/null 2>/dev/null && die "OpenAPS already running: exiting" && exit
touch /tmp/openaps.lock
getpumpsettings
