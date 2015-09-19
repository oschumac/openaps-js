#!/usr/bin/env node

function getTime(minutes) {
    var baseTime = new Date();
    baseTime.setHours('00');
    baseTime.setMinutes('00');
    baseTime.setSeconds('00');    
    
    return baseTime.getTime() + minutes * 60 * 1000;
   
}

/* Return basal rate(U / hr) at the provided timeOfDay */

function basalLookup() {
    var now = new Date();
    basalRate = Math.round(basalprofile_data[basalprofile_data.length-1].rate*100)/100
    
    for (var i = 0; i < basalprofile_data.length - 1; i++) {
        if ((now >= getTime(basalprofile_data[i].minutes)) && (now < getTime(basalprofile_data[i + 1].minutes))) {
            basalRate = basalprofile_data[i].rate.toFixed(2);
            break;
        }
    }
}


function isfLookup() {
    var now = new Date();
    //isf_data.sensitivities.sort(function (a, b) { return a.offset > b.offset });
    var isfSchedule = isf_data.sensitivities[isf_data.sensitivities.length - 1]
    
    for (var i = 0; i < isf_data.sensitivities.length - 1; i++) {
        if ((now >= getTime(isf_data.sensitivities[i].offset)) && (now < getTime(isf_data.sensitivities[i + 1].offset))) {
            isfSchedule = isf_data.sensitivities[i];
            break;
        }
    }
    isf = isfSchedule.sensitivity;
}


if (!module.parent) {
    
    var glucose_input = process.argv.slice(2, 3).pop()
    var clock_input = process.argv.slice(3, 4).pop()
    var iob_input = process.argv.slice(4, 5).pop()
    var basalprofile_input = process.argv.slice(5, 6).pop()
    var currenttemp_input = process.argv.slice(6, 7).pop()
    var isf_input = process.argv.slice(7, 8).pop()
    var requestedtemp_input = process.argv.slice(8, 9).pop()
    var profile_data_input = process.argv.slice(9, 10).pop()
    
    if (!glucose_input || !clock_input || !iob_input || !basalprofile_input || !currenttemp_input || !isf_input || !requestedtemp_input || !profile_data_input) {
        console.log('usage: ', process.argv.slice(0, 2), '<glucose.json> <clock.json> <iob.json> <current_basal_profile.json> <currenttemp.json> <isf.json> <requestedtemp.json> <profile.json>');
        process.exit(1);
    }
    
    var cwd = process.cwd()
    var profile_data = require(cwd + '/' + profile_data_input);
    var glucose_data = require(cwd + '/' + glucose_input);
    var bgTime;
    if (glucose_data[0].display_time) {
        bgHHMMSS = glucose_data[0].display_time.split(" ")[1];
        //bgTime = new Date(glucose_data[0].display_time.replace('T', ' '));
    } else if (glucose_data[0].dateString) {
        bgDate = new Date(glucose_data[0].dateString);
        bgHHMMSS = bgDate.toTimeString().split(' ')[0];
    } else { console.error("Could not determine last BG time"); }
    bgHH = bgHHMMSS.split(':')[0];
    bgMM = bgHHMMSS.split(':')[1];
    bgTime = bgHH + ":" + bgMM;
    var bgnow = glucose_data[0].glucose;
    var delta = bgnow - glucose_data[1].glucose;
    var tick;
    if (delta < 0) { tick = delta; } else { tick = "+" + delta; }
    var clock_data = require(cwd + '/' + clock_input);
    var pumpHHMMSS = clock_data.split("T")[1];
    pumpHH = pumpHHMMSS.split(':')[0];
    pumpMM = pumpHHMMSS.split(':')[1];
    pumptime = pumpHH + ":" + pumpMM;
    var iob_data = require(cwd + '/' + iob_input);
    iob = iob_data.iob.toFixed(1);
    var basalprofile_data = require(cwd + '/' + basalprofile_input);
    var basalRate;
    basalLookup();
    var temp = require(cwd + '/' + currenttemp_input);
    var tempstring;
    if (temp.duration < 1) {
        tempstring = "Keine TBR";
    } else {
        tempstring = "TBR: " + temp.duration + "m@" + temp.rate.toFixed(1);
    }
    var isf_data = require(cwd + '/' + isf_input);
    var isf;
    isfLookup();
    var eventualBG = Math.round( bgnow - ( iob * isf ) );
    var requestedtemp = require(cwd + '/' + requestedtemp_input);
    var reqtempstring;
    if (typeof requestedtemp.duration === 'undefined') {
        reqtempstring = "Keine neue TBR";
    }
    else if (requestedtemp.duration < 1) {
        reqtempstring = "Abbruch";
    } else { 
        reqtempstring = requestedtemp.duration + "m@" + requestedtemp.rate.toFixed(1) + "U";
    }

    maxSafeBasal = Math.min(profile_data.max_basal, 3 * profile_data.max_daily_basal, 4 * profile_data.current_basal);

    var pebble = {        
        "content" : "BZ:" + bgnow + tick + " " + bgTime + "\n"
        + "IOB:" + iob + "U->" + requestedtemp.eventualBG + "/" + requestedtemp.snoozeBG + "\n"
        + tempstring + "\n" 
        + "Progr: " + basalRate + "U/h\n"
        + "um " + pumptime + "\n"
		+ "Req: " + reqtempstring + "\n"
		+ "BZ avg:" + requestedtemp.bg + "\n"
        + requestedtemp.reason + "\n"
		+ "SafeBasal -> " + maxSafeBasal ,
        "refresh_frequency": 1
    };

    console.log(JSON.stringify(pebble));
}
