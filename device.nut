#require "button.class.nut:1.2.0"
#require "WS2812.class.nut:3.0.0"

// call this first.
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 30.0);

// ** Set up for WS2812 led settings.
NUMPIXELS <- 13;
 
// Instantiate the WS2812s
spi <- hardware.spi257;
spi.configure(MSB_FIRST, 7500);
pixels <- WS2812(spi, NUMPIXELS);
hardware.pin1.configure(DIGITAL_OUT, 1);


// ** Set up for the RGB led settings and functions for 3pin RGB
// redPin <- hardware.pin1;
// greenPin <- hardware.pin5;
// bluePin <- hardware.pin2;

// redPin.configure(PWM_OUT, 1.0/400.0, 0.0);
// greenPin.configure(PWM_OUT, 1.0/400.0, 0.0);
// bluePin.configure(PWM_OUT, 1.0/400.0, 0.0);

// start up in yellow flashing state, until connected to agent 
// to retrieve current state
red <- 10;   // 0 - 255
green <- 10; // 0 - 255
blue <- 0;  // 0 - 255

state <- 3; // 0 = off, 1 = on, 2 = flashingQuickly, 3 = flashingSlowly
// states 2 & 3 are device only states in that they indicates only local events
// like when the button has been pressed and is waiting for an update
// from the server, or when it is not connected to the network.
state2Interval <- 0.1;
state3Interval <- 0.5;



function sendInfo(theAction = "") {
    agent.send("info", {
        color = {"red" : red, "green" : green, "blue" : blue},
        state = state
        action = theAction
    });
}

function setColor(colors) {
    //colors <- inputs.colors
    foreach(i, tcolor in colors) {
        tcolor = tcolor.tointeger();
        if (tcolor < 0) colors[i] = 0;
        if (tcolor > 255) colors[i] = 255;
    }

    red = colors.red;
    green = colors.green;
    blue = colors.blue;
    
    update();
}

function setState(s) {

    state = s.tointeger();
    
    server.log("in setState and the state is set to : " + state);

    update();
}

function ledsOn() {

    // Write the color data to the WS2812s
    pixels.fill([red, green, blue])
        .draw();

    if (state == 2) {
        imp.wakeup(state2Interval, ledsOff);
    } else if (state ==3) {
        imp.wakeup(state3Interval, ledsOff);
    }
}

function ledsOff() {
    // turn the WS2812s off
    pixels.fill([0,0,0])
        .draw();

    if (state == 2) {
        imp.wakeup(state2Interval, ledsOn);
    } else if (state == 3) {
        imp.wakeup(state3Interval, ledsOn);
    } else {
        update(); // redo when state has been reset from Agent.
    }

}

function update() {
    // if LED is 3 pin RGB then use this code block
    // *TODO* fix this to new flashing code above !!
    // if (state == 0) {
    //     redPin.write(0);
    //     greenPin.write(0);
    //     bluePin.write(0);
    // } else {
    //     redPin.write(red/255.0);
    //     greenPin.write(green/255.0);
    //     bluePin.write(blue/255.0);
    // }
    // end code block
    

    // if led is of the WE2812 SPI variety use this code block
    if (state == 0) {
        ledsOff();
    } else {
        ledsOn();
    }

}

// Handle actions from Agent/Server
agent.on("setColor", setColor);
agent.on("setState", setState);
agent.on("getInfo", sendInfo);


// On device buttons for turning on or off the led state.
function resetButtonPushed(buttonNumber) {
    
    // set button to blue on device for user feedback
    // server will reset it properly when it responds
    // Only do this if the device is online
    if (server.isconnected()) {
    //if (2==3) {
        local icolor = { red= 0, green= 0, blue=10};
        setColor(icolor);
        setState(2);
        agent.send("resetButtonPushed", {});
    } else {
        // set state to 3.
        setState(3);
        update();
    }
    
}

// On device buttons for turning on or off the led state.
// *TODO* better way to tell code which pin the button is on !
button1 <- Button(hardware.pin8, DIGITAL_IN_PULLUP);

button1.onPress(function() {
    server.log("Button1 Pressed!");
    resetButtonPushed(1);
});

button2 <- Button(hardware.pin2, DIGITAL_IN_PULLUP);

button2.onPress(function() {
    server.log("Button2 Pressed!");
    resetButtonPushed(2);
});

button3 <- Button(hardware.pin5, DIGITAL_IN_PULLUP);

button3.onPress(function() {
    server.log("Button3 Pressed!"); 
    resetButtonPushed(3);
});

// Manage internet connection manually to show connection status via LED.
function mainConnectionMonitoringLoop() {
    server.log("in the Main connection loop !!");
    // Wake-up every minute and try to connect if disconnected.
    imp.wakeup(60.0, mainConnectionMonitoringLoop);    
    
    if (server.isconnected()) {
        server.log("server is connected !!!")
    } else {
        setState(3); // indicate to the user that we are 
        update();
    }
    
    server.connect(connectingHandler, 30.0);
}

function coldStart() {
    // just need this in a call back for a slight delay.
    agent.send("coldstart", {});
}

function connectingHandler(reason) {
    
    server.log("is this getting called ?")

	if (reason == SERVER_CONNECTED) {
		// Device has successfully connected
		server.log("Device back online get data from Agent");
		//give the device a second to come online.
		imp.wakeup(1.0, coldStart);

	}
}

function setPowersaveMode() {
    server.log("setting imp to powersave mode");
    // see what this does to web commands latency.
    imp.setpowersave(true);
}

// set the device to flashing slowly in last known state 
// when disconnected from internet
function disconnectedState(reason) {
    // can't log the reason if we are off line.
    setState(3);
    update();
}

server.onunexpecteddisconnect(disconnectedState);

impData <- imp.info();
server.log("the imp info is: ");
server.log(impData.type);

// Statup code.
update();
agent.send("coldstart", {});
imp.wakeup(10.0, mainConnectionMonitoringLoop);
imp.wakeup(5.0, setPowersaveMode);
