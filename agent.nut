#require "Rocky.class.nut:2.0.0"
#require "Loggly.class.nut:1.1.0"

// Want to try logging all the activity in loggly.
loggly <- Loggly("1952c634-6e97-4820-bfaa-63a6ed10cf8e", { "tags" : "BAS_LED_Logging_test",
                                            "timeout" : 10,
                                            "limit" : 100});


/******************** Variables ********************/
led <- {
    color = { red = 10, green = 10, blue = 0 },
    state = 1
};

startupState <- true;

heartbeatCounter <- 0;
agentUniqueId <- split(http.agenturl(), "/").pop();

server.log("Agent URL is: " + http.agenturl());
server.log("Unique id is: " + agentUniqueId);


/******************** State / Persistance ************/
// persist state in local cloud storage
function saveState() {
    server.log("In agent saving state");
    server.save({ "deviceState" : led });
}

function retrieveState() {
    server.log("In agent retreiving state");
    local retrievedState = server.load(); 
    
    if ("deviceState" in retrievedState) {
        led = retrievedState.deviceState;
    }
    // else just use the initialized value
    
    // server.log("the retrieved state is ... ");
    // server.log(http.jsonencode(retrievedState));
    // server.log("the led is ... ");
    // server.log(http.jsonencode(led));
}

/***************** Calls from Device **********************/
device.on("coldstart", function(nothing) {
    server.log("device starting up send it our current state");

    device.send("setColor", led.color);
    device.send("setState", led.state);

});

device.on("resetButtonPushed", function(data) {
    
    server.log("Call the Imp reminder server to reset the state of the reminder");
    // Setting up Data to be POSTed
    local payload = {
        idToBeReset = imp.configparams.deviceid,
        agentUrl = http.agenturl(),
        key = "your_apikey",
        origin = "buttonpres",
        platform = "electricimp",
        args = http.jsonencode(led),
        version = "0.0.9"
    };
    
    server.log(imp.configparams.deviceid);
    
    // encode data and log
    local headers = { "Content-Type" : "application/json" };
    local body = http.jsonencode(payload);
    local url = "https://calm-reef-94526.herokuapp.com/api/impdevice/agentcall/reset";
    HttpPutWrapper(url, headers, body, false);
    
});

// Http Put Request Handler
function HttpPutWrapper (url, headers, string, log) {
  local request = http.put(url, headers, string);
  local response = request.sendsync();
  if (log)
    server.log("returned from the call to the backend");
    server.log(http.jsonencode(response));
  return response;
}


/******************  Device Cloud API ****************/
defaults <- {
    accessControl = true,
    allowUnsecure = false,
    strictRouting = false,
    timeout = 10
}

app <- Rocky(defaults);

// This seems to be needed to pass preflight checks
app.on("OPTIONS", ".*", function(context) {
    context.send("OK");
});

app.get("/color", function(context) {
    context.send(200, { color = led.color });
});

app.get("/state", function(context) {
    
    // increment heartbeat counter & check
    heartbeatCounter += 1;
    if (heartbeatCounter > 100) {
        // Just put the Loggly stuff in here for now to see how it works
        loggly.log({
            "timestamp" : Loggly.ISODateTime(time()),
            "event" : "Heartbeat Status",
            "color" : led.color,
            "state" : led.state
        });
        
        heartbeatCounter = 0;
    }
    
    context.send(200, { state = led.state });
    
});
app.post("/color", function(context) {
    try {
        // Preflight check
        if (!("color" in context.req.body)) throw "Missing param: color";
        if (!("red" in context.req.body.color)) throw "Missing param: color.red";
        if (!("green" in context.req.body.color)) throw "Missing param: color.green";
        if (!("blue" in context.req.body.color)) throw "Missing param: color.blue";

        // if preflight check passed - do things
        led.color = context.req.body.color;
        device.send("setColor", context.req.body.color);
        device.send("setState", 1); // always state 1 on set color
        saveState();
        
        // LOG THE EVENT
        loggly.log({
            "timestamp" : Loggly.ISODateTime(time()),
            "event" : "Color Set From API",
            "color" : context.req.body.color,
            "state" : led.state
        });
    
    
        // send the response
        context.send({ "verb": "POST", "led": led });
    } catch (ex) {
        context.send(400, ex);
        return;
    }
});

app.post("/state", function(context) {
    try {
        // Preflight check
        if (!("state" in context.req.body)) throw "Missing param: state";
    } catch (ex) {
        context.send(400, ex);
        return;
    }

    // if preflight check passed - do things
    led.state = context.req.body.state;
    device.send("setState", context.req.body.state);
    saveState();
    
    // LOG THE EVENT
    loggly.log({
        "timestamp" : Loggly.ISODateTime(time()),
        "event" : "State Set From API",
        "color" : led.color,
        "state" : context.req.body.state
    });


    // send the response
    context.send({ "verb": "POST", "led": led });
});


//****************** startup code ********************/


// get the last saved state.
retrieveState();    
