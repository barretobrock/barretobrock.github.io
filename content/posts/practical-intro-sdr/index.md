---
title: 'A Practical Intro to SDR and Daemonization'
draft: false
date: 2022-04-01T00:00:00-05:00
lastmod: 2025-04-20T10:32:46-05:00
tags: 
  - projects
  - python
categories:
  - home-automation
---

Software-defined radios (SDR) are an amazing thing. Without turning any knobs or sliding any sliders, you're often able to adjust the radio frequency with just a few commands to the machine that's connected to the device. While typically you can use SDR to not only receive signals, but also transmit, this post will cover just a very basic, but hopefully practical, intro into using SDR.

### Why do this?

We have a lot of ways to gather data around the house these days. The data I've generally been the most interested in for the longest time has been temperature. There are a lot of great temp sensors one can procure for various device systems these days. A lot of companies that are temp data adjacent will even offer sensors that interface with their devices: My HVAC controller offers this, as does many other manufacturers in that realm and the general home automation realm. It's both neat and seemingly relieving to know that there's so many options to choose from. 

And yet, these days you also can't seem to just "buy" a sensor product without considering the ramifications of the purchase. Some sensors have proprietary technology that renders it unusable outside of that one manufacturer's domain. It can be difficult to purchase an already expensive sensor when you consider that you're going to have to trust that the company won't suddenly go defunct or simply decide they don't support your sensor's model anymore (but you can certainly buy the new model!). Taking this into consideration, I wanted to see how difficult it would be to build out a fairly flexible system of temp sensors.

### Goals
For this system to work, I needed to map out some goals to make sure I'd select the ideal components for success:
 - Relatively cheap temp sensors
 - The sensors should all operate on the same frequency
 - Sensors should be battery powered, and the batteries should last longer than 60 days in normal conditions
 - The SDR should allow for constant use over months
 - The SDR should allow access from an automation script that collects the data received

### Materials
Considering the above goals, I ended up selecting the [NooElec MiniSDR](https://www.nooelec.com/store/sdr/nesdr-mini.html), which comes as a convenient USB stick. For the temperature sensor, I ended up going with the [AcuRite Model 11112-609TXC](https://www.acurite.com/products/indoor-outdoor-temperature-humidity-sensor?variant=41330220335217), namely because various forum posts suggested that its broadcast frequency at 433MHz was ideal for this kind of project - namely, that signal is quite common for such devices to use, so it's likely I might be able to incorporate other, unrelated devices to the same system.

In all, getting both the SDR and 2 sensors cost about the same as getting one add-on sensor from my HVAC controller's system, though granted that sensor a) didn't require as much setup and b) probably was better optimized for battery operation. One thing to note, though, was that the sensor also included a fancy occupancy detection feature that I honestly wasn't sure I really even needed :).

### Installation

First, I plugged in the SDR to one of my home servers. It's nothing fancy, just a mini pc that's running in "headless" (i.e., no screens) mode, so I have to access it through another machine that has a screen (typically this is done via SSH).

Next, I had to install some system-wide software to allow me to interface with the USB SDR. As my server has gone from running Ubuntu to running Arch Linux, the dependencies I needed to install have differed based on the OS used:

**For Ubuntu**

```bash
sudo apt install libtool libusb-1.0-0-dev librtlsdr-dev rtl-sdr build-essential autoconf cmake pkg-config
```

**For Arch / Manjaro**

```shell
sudo pacman -Sy libtool libusb rx_tools rtl-sdr autoconf cmake pkg-config
```

Next, I cloned the [rtl_433](https://github.com/merbanan/rtl_433) repo locally. This repo helps with interfacing with the SDR and receiving the data from the 433MHz band (though note that this repo actually handles other bands as well!).
```shell
git clone https://github.com/merbanan/rtl_433.git ~/extras/rtl_433/
```

Per the instructions on that last repo, I built and installed `rtl_433` locally:
```shell
cd rtl_433/
mkdir build
cd build
cmake ..
make
make install
```

### Creating the daemons

Next, I had to create two daemons: one to stream, one to collect. The streaming one just 'listens' to the SDR and forwards the info so that the collection service can do its thing. The collection service filters through that info and bundles the info it picks up, then saves it at regular intervals. 

If you're new to computing, the term 'daemon' just means we're creating something that is meant to run in the background without us controlling it in any way.   
> **Fun fact** - The term daemon doesn't mean that computing has some sort of connection with the Underworld. The term was actually borrowed from Greek mythology, where daemons were supernatural beings tirelessly working in the background.  

To make these daemons, I just wrote the stream and collect processes in Python. Note that I use [loguru](https://loguru.readthedocs.io/en/stable/) in a lot of my projects for easier logging setup & review. You don't have to include that, of course. 
```python {title = "../stream/rf_stream.py"}
import subprocess

from loguru import logger

serv_ip = "ip_of_server"

cmd = ['/usr/local/bin/rtl_433', '-F', f'syslog:{serv_ip}:1433']

logger.info(f'Sending command: {" ".join(cmd)}')
process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
process_output, _ = process.communicate()
logger.debug(f'Process output: {process_output}')
```

```python {title = "../collect/rf_collect.py"}
#!/usr/bin/env python3
"""
ETL for RTL_433 json objects via syslog -> processed Dataframe -> influx

Note: depends on `rf_stream` already being running and feeding data to port 1433
    via `rtl_433 -F syslog::1433`
"""
from datetime import datetime
import json
from json import JSONDecodeError
from pathlib import Path
import signal
import socket
from typing import (
    Dict,
    List,
    Optional,
    Union
)

from loguru import logger
import pandas as pd
import yaml


class GracefulKiller:
    """Means of gracefully killing a script upon SIGTERM/SIGINT command
    reception via systemd

    Example:
        >>> killer = GracefulKiller()
        >>> # Some other code...
        >>> while not killer.kill_now:
        >>>     # ...
        >>>     # spooky daemony stuff here
        >>>     # ...
        >>> # If we're here, systemd sent a SIGINT/SIGTERM command.
        >>> # Now we can close out connections and log objects
        >>> db_connection.close()
        >>> log.close()
    """
    def __init__(self):
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)
        self.kill_now = False

    def exit_gracefully(self, signum, frame):
        """Sets the kill_now property to True,
        which allows the script to exit the while loop"""
        self.kill_now = True

        
def parse_syslog(ln: bytes) -> str:
    """Try to extract the payload from a syslog line."""
    ln = ln.decode("ascii")  # also UTF-8 if BOM
    if ln.startswith("<"):
        # fields should be "<PRI>VER", timestamp, hostname, command, pid, mid, sdata, payload
        fields = ln.split(None, 7)
        ln = fields[-1]
    return ln


DATA_DIR = Path().home().joinpath('data/rf')
DATA_DIR.mkdir(exist_ok=True)
unknown_devs_file = DATA_DIR.joinpath(f'unknown_devs_{datetime.today():%F}.csv')

UDP_IP = "ip_of_server"
UDP_PORT = 1433

hass = HAHelper()
killer = GracefulKiller()

# device id to device-specific data mapping
mappings: Dict[int, Dict[str, Union[str, Optional[int], List[Dict[str, str]]]]]
mappings = yaml.safe_load(Path(__file__).parent.joinpath('nodes.yaml').open())

# Map the names of the variables from the various sensors to what's acceptable in the db
possible_measurements = ['temperature_C', 'humidity']

logger.debug('Establishing socket...')
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.bind((UDP_IP, UDP_PORT))

unknown_devs_df = pd.DataFrame()
last_dt = datetime.now().date()     # For reporting daily unknown devices
start_s = int(datetime.now().timestamp())
interval_s = 60     # Update values every minute

logger.debug('Beginning loop!')
while not killer.kill_now:
    line, _addr = sock.recvfrom(1024)
    # Convert line from bytes to str, prep for conversion into dict
    line = parse_syslog(line)
    data = None
    try:
        data = json.loads(line)
    except JSONDecodeError as e:
        logger.error(e, f'Unable to parse this object. Skipping. \n {line}')
        continue

    if "model" not in data:
        # Exclude anything that doesn't contain a device 'model' key
        logger.info('Skipping, missed "model" key: '
                  f'{json.dumps(data, indent=2)}')
        unknown_devs_df = pd.concat([unknown_devs_df, pd.DataFrame(data, index=[0])])
        continue

    # Begin processing the data
    if data is not None:
        # Begin extraction process
        dev_id = data.get('id')
        rcv_time = data.get('time')
        dev_model = data.get('model')
        logger.debug(f'Receiving from device: {dev_model} ({dev_id})')
        if dev_id in mappings.keys():
            # Device is known sensor... record data
            dev_dict = mappings[dev_id]
            name = dev_dict['name']
            friendly_name_prefix = dev_dict['friendly_name_prefix']
            sensors = dev_dict['sensors']  # type: List[Dict]
            last_update = dev_dict.get('last_update', start_s)
            logger.debug(f'Device identified. Name: {name}.')
            if datetime.now().timestamp() - last_update > interval_s:
                logger.debug('Interval lapsed. Sending measurements to HASS...')

                for sensor in sensors:
                    data_name = sensor.get('data_name')
                    if data_name not in data.keys():
                        logger.info(f'Skipped sensor {data_name}, as it wasn\'t in the list of data keys offered: '
                                  f'{",".join(data.keys())}')
                        continue
                    attributes = sensor['attributes']

                    device_class = attributes.get('device_class', 'unk')
                    if 'friendly_name' not in attributes.keys():
                        attributes['friendly_name'] = f'{friendly_name_prefix} {device_class.title()}'

                    hass.set_state(
                        device_name=f'sensor.rf_{name}_{device_class}',
                        data={'state': data[data_name]},
                        attributes=attributes
                    )
                mappings[dev_id]['last_update'] = int(datetime.now().timestamp())
        else:
            logger.info(f'Unknown device found: {dev_model}: ({dev_id})\n'
                      f'{json.dumps(data, indent=2)}')
            unknown_devs_df = pd.concat([unknown_devs_df, pd.DataFrame(data, index=[0])])

    if last_dt != datetime.now().date() and unknown_devs_df.shape[0] > 0:
        # Report on found unknown devices
        logger.debug(f'Saving {unknown_devs_df.shape[0]} unknown devs to file...')
        unknown_devs_df.to_csv(unknown_devs_file, index=False, sep=';', mode='a')
        logger.debug('Resetting unknown device df.')
        unknown_devs_df = pd.DataFrame()
        unknown_devs_file = DATA_DIR.joinpath(f'unknown_devs_{datetime.today():%F}.csv')
        last_dt = datetime.now().date()


logger.debug('Collection ended.')
```

Ok, that last file was a lot to break down. Stay with me here! Here's an overview of the process:
1. First, we're going to read in a YAML (think: a more flexible cousin of the CSV) file with all the known device IDs for the sensors we're interested in
2. Next, we also want to track unknown devices just in case we're missing out on any other devices nearby sending us interesting data. This info will be stored in a separate CSV. It's not important to the process, but might yield some neat info we can later decide to incorporate
3. We connect to the streaming daemon and listen for data it sends our way. To avoid losing data, we wrap this listening service in a `GracefulKiller` class that equally listens for a signal from the machine that tells the process to kindly stop immediately. It's like having the waitstaff at a Waffle House politely ask you to get down from the table before actually calling the cops (AKA the program is able to end 'gracefully' and not be stopped abruptly by the system, which could result in malformed data!).
4. If we actually get data that's not empty (`if data is not None`), we start to process the details of the signal we received. Most devices will include in the payload things like the device id, the time it was sent, the model, etc. 
5. Having the device id, we look up the id to see if it's one that we care about. If it is, we proceed with the regular process. If it isn't, we just throw all the details we received about this device into the "unknown_devices" bin (so to speak)
6. Assuming the device is one we care about, we retrieve details about it from our mapping. One of the details is when we last collected info about this device. We clearly don't need to know every single instance that this device transmits to us. Rather, we want to capture these details over time. Knowing that, we're going to verify that we haven't collected data from this device within the last `interval_s` seconds. Assuming that's `True`, we proceed...
7. ...and prepare a new payload to forward the data to whatever place we want to send it. In this example, we're sending the data onward to HomeAssistant, where the devices exist as sensors. We process the sensors' data for both temp and humidity and forward along so that they can be used in the HomeAssistant dashboard & automations. 
8. All that's remaining is for us to unload the "unknown_devices" bin every once in a while. You want to make sure you dump data like this relatively frequently to avoid a gradual buildup of unimportant data stored in memory. For a long-running process like this, that's a real risk, though granted we're only talking about tens of unknown devices. 

_<<takes a deep breath>>_ That's it!

Now that we've written out the scripts, how do we go about actually daemonizing these?

### The Power of `chmod` Compels You - Or, Daemonizing Your Scripts With a Service File

Daemonization isn't actually that hard. You just need to create what's essentially a config file, move it to the right spot and then 'register' it with your machine so it knows where & how to run the script associated with the daemon. Note, though, that this isn't the only way to daemonize scripts.

First off, let's create our 'config' file. Here's a template for ya:
```service {lineNos=inline, title="example_rf_collect.service"}
[Unit]
Description=RTL 433 Data Collection Service
After=multi-user.target

[Service]
User=<user>
Group=<user>
Type=idle
ExecStart=/path/to/your/venv/bin/python3 /path/to/your/project/collect/rf_collect.py
WorkingDirectory=/path/to/your/project
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Next, we're going to copy that file from wherever it is to where the system expects it to be by default
```shell
sudo cp /path/to/example_rf_collect.service /lib/systemd/system/example_rf_collect.service
```
Then, we'll change the permissions so only the owner can read/write, but others can only read
```shell
sudo chmod 644 /lib/systemd/system/example_rf_collect.service
```
Last, we're going to refresh the process that controls the daemon 'registry' so that it can 'see' the new service config, then we're going to hook it so that it will run after the machine boots. This is a key benefit of running a daemon, as you wouldn't need to remember to run the script.
```shell
sudo systemctl daemon-reload
sudo systemctl enable /lib/systemd/system/example_rf_collect.service
```

Repeat the above sequence for the other service file and then we're ready to move on!

### Starting the Daemons

Once we're ready, we just start the daemons by referring to only their file name (since they're now registered).
```shell
sudo systemctl start example_rf_collect.service
```

If you have issues, you can always check on the status of the service with:
```shell
sudo systemctl status example_rf_collect.service
```
...or stop the service entirely with
```shell
sudo systemctl stop example_rf_collect.service
```
You can also check your log output with
```shell
sudo journalctl -u example_rf_collect.service -f -n 100
```
- `-u` filters on the service
- `-f` initiates 'tail' mode, where you continuously get new entries as they're received
- `-n` renders the last N lines of the logs received

Last, you can also run the script itself (from `ExecStart`) in your own terminal to make sure it's functioning properly if you have any issues with the service not starting properly:
```shell
/path/to/your/venv/bin/python3 /path/to/your/project/collect/rf_collect.py
```

### Conclusion

So this is just one way of how to build your own sensor network without having to buy in to a single manufacturer's realm of devices.

After running this script for a few days, I noticed a lot of nearby, unknown devices that my radio was also picking up: 
 - Other people's temp sensors (most were the kind that are connected to the displays and typically placed near a window)
 - Various Tire Pressure Monitoring System (TPMS) sensors
 - A few door & window sensors that would send new status updates when opened or closed (!!)
 - A single unknown device that I wasn't quite sure what it actually did, but it sent a serial number of sorts as its only payload

Here's hoping my documentation of this is found helpful by someone. If you spot any errors in my above attempts at communicating any concept, feel free to reach out! I'd be happy to correct my details.
