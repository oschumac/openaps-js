# yes, with some modifications/plugin
# for that I would make a bash script that uses nightscout rest api
# then tell openaps to use the bash script as a "device" using the process/shell type
# so in bash script curl -s mynightscout/api/v1/entries.json?count=10 or something similar
# then add it to openaps as nightscout device with the "process" type



curl -s http://yoursite.azurwebsites.net/api/v1/entries.json?count=20 >glucose.json
sed -i s/sgv/glucose/g glucose.json
sed -i s/mbg/glucose/g glucose.json
sed -i s/direction/trend_arrow/g glucose.json 
sed -i s/dateString/display_time/g glucose.json
sed -i s/PM/" "/g glucose.json

echo "  " >> glucose.json 
echo "  " >> glucose.json 


