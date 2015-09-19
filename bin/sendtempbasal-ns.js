var http = require('https');

if (!module.parent) {
    var iob_input = process.argv.slice(2, 3).pop()
    var enacted_temps_input = process.argv.slice(3, 4).pop()
    var glucose_input = process.argv.slice(4, 5).pop()
    var profile_input = process.argv.slice(5, 6).pop()
	var reqtemp_input = process.argv.slice(6, 7).pop()
	
    if (!iob_input || !enacted_temps_input || !glucose_input || !profile_input) {
        console.log('usage: ', process.argv.slice(0, 2), '<iob.json> <enactedBasal.json> <bgreading.json> <profile.json> <requestedtemp.json>');
        process.exit(1);
    }
}

var glucose_data = require('./' + glucose_input);
var enacted_temps = require('./' + enacted_temps_input);
var iob_data = require('./' + iob_input);
var profile_data = require('./' + profile_input);
var reqtemp_data = require('./' + reqtemp_input);

var data = JSON.stringify({
	"enterdBy": 'OpenAPS Controller',
	"eventType": 'APS_TEMP',
	"glucose": Math.floor(((enacted_temps.rate * 50) + 50)), 
	"glucoseType": 'fake',
	"insulin": enacted_temps.rate, 
	"notes": 'BZ: ' + glucose_data[0].glucose + ' ,BZ mittel: ' + reqtemp_data.bg + ', eventualBZ ' + reqtemp_data.eventualBG+ ' TBR Zeit : ' + enacted_temps.duration + ' TBR Rate U/min: ' + enacted_temps.rate +  ' Prog Rate: ' + profile_data.current_basal + ' IOB: ' + (Math.round(100.0 * iob_data.iob) / 100.0) + ' APS Logik: ' + reqtemp_data.reason ,
	"units": 'mg/dl',
	"created_at" : enacted_temps.timestamp
}
);

var options = {
    host: 'yoursite.azurewebsites.net',
    port: '443',
    path: '/api/v1/treatments/',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': data.length
    }
};

var req = http.request(options, function (res) {
    var msg = '';
    
    res.setEncoding('utf8');
    res.on('data', function (chunk) {
        msg += chunk;
    });
	
    res.on('end', function () {
        console.log(JSON.parse(msg));
    });
	
});

console.log(JSON.parse(data));

req.write(data);
req.end();
