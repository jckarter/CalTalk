function setVersion(ver) {
    var els, i;
    if(ver == "Panther" || ver == "Tiger") {
	els = document.getElementsByName("pantherOnly");
	for(i = 0; i < els.length; ++i)
	    els[i].style.display = (ver == "Panther"? "inline" : "none");
	
	els = document.getElementsByName("tigerOnly");
	for(i = 0; i < els.length; ++i)
	    els[i].style.display = (ver == "Tiger"? "inline" : "none");
	
	els = document.getElementsByName("version");
	for(i = 0; i < els.length; ++i)
	    if(ver == "Panther")
		els[i].innerHTML = 'MacOS 10.3 "Panther"';
	    else if(ver == "Tiger")
		els[i].innerHTML = 'MacOS 10.4 "Tiger" or higher';
    }
}

function detectVersion() {
    if((navigator.userAgent).match(/WebKit\/3\d\d/))
	setVersion("Panther");
    else if((navigator.userAgent).match(/WebKit\/([456789]|\d\d)\d\d/))
	setVersion("Tiger");
    else {
	alert('You are running an unsupported version of MacOS, or I otherwise could not determine your MacOS version. I will display instructions for OS 10.3 "Panther".');
	setVersion("Panther");
    }
}