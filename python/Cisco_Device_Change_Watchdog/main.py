""" 
ABOUT
Script that checks for changes in Cisco devices that are in a devices.txt list.
The changes are saved in an HTML file showing diffs

SUMMARY
1. Check for existing config for this Cisco device in the "current" folder. If not, create config file and save it
2. Load the config from the "current" folder
3. Get running config from device
4. Check the two for differences
5. If there are differences, create changelog file in "changelog" folder
6. If there are differences, send email
7. Save current config to "current" folder and move the previous one to "archive" folder
"""

from netmiko import ConnectHandler, NetmikoAuthenticationException
import os
import glob
from datetime import datetime, timedelta
import difflib
import logging
from dotenv import load_dotenv

date = datetime.now().date()

load_dotenv(".env")

# create .env file with the below credentials used to login to Cisco devices
DEVICE_USERNAME = os.environ.get("DEVICE_USERNAME")
DEVICE_PASSWORD = os.environ.get("DEVICE_PASSWORD")
RETENTION_FILE_NUMBER = 2
RETENTION_DAYS = 30

dir = ''
configs_dir = f'{dir}/configs'
archive_dir = f'{configs_dir}/archive/'
current_dir = f'{configs_dir}/current/'
changelog_dir = f'{configs_dir}/changelog/'
# list of IPs for each Cisco device to login to
devices_file = f'{configs_dir}/devices.txt'
logs_dir = f'{configs_dir}/logs/'

# Make sure files and directories exist
if not os.path.exists(configs_dir):
    os.mkdir(configs_dir)

if not os.path.exists(archive_dir):
    os.mkdir(archive_dir)

if not os.path.exists(current_dir):
    os.mkdir(current_dir)

if not os.path.exists(changelog_dir):
    os.mkdir(changelog_dir)

if not os.path.exists(logs_dir):
    os.mkdir(logs_dir)

if not os.path.exists(devices_file):
    raise FileNotFoundError('devices.txt file is missing!')

# Setup logging
logging.basicConfig(
    filename=logs_dir + f'log_{date}.log',
    format='%(asctime)s,%(msecs)d %(levelname)s %(message)s',
    datefmt='%H:%M:%S',
    level=logging.INFO
)
logging.info('Beginning config change checker')

# Cleanup archive and changelog folders
retention_date = datetime.now() - timedelta(days=RETENTION_DAYS)


def cleanup_folder(directory, retention_date, file_number=None):
    logging.info(f'Cleaning up folder "{directory}"')
    all_files = glob.iglob(f'{directory}/**/*', recursive=True)
    for entry in all_files:
        entry_path = entry.replace('\\', '/')
        if os.path.isdir(entry_path):
            continue
        elif os.path.isfile(entry_path):
            file_created_time = datetime.fromtimestamp(
                os.stat(entry_path).st_ctime)
            if file_number and len(os.listdir(os.path.dirname(entry_path))) <= file_number:
                logging.info(
                    f'Retaining "{entry_path}" to keep at least {file_number} versions.')
                continue
            elif file_created_time < retention_date:
                logging.info(f'Purging "{entry_path}"')
                os.remove(entry_path)
            else:
                logging.info(
                    f'Retaining "{entry_path}" until {(file_created_time + timedelta(days=RETENTION_DAYS)).strftime("%Y-%m-%d")}')


logging.info('Checking for current configs for all devices')
with open(devices_file, 'r') as file:
    for line in file:
        # Check for existing config for this device in the "current" folder. If not, create config file and finish with that device
        device = line.strip()
        logging.info(f'{device} - Beginning check')
        if not os.path.exists(current_dir + f"{device}.txt"):
            logging.info(
                f'{device} - No config found. Copying config. Will check for differences next run since there was no previous config current')
            try:
                output = None
                device_connection = ConnectHandler(
                    device_type='cisco_ios', ip=device, username=DEVICE_USERNAME, password=DEVICE_PASSWORD)
                output = device_connection.send_command("show run")
                file_write = open(
                    current_dir + f"{device}.txt", "w")
                file_write.write(output)
                file_write.close()
                device_connection.disconnect()
            except NetmikoAuthenticationException:
                logging.warning(
                    f'Unable to login with {DEVICE_USERNAME} user.')
            except Exception as error:
                logging.error(
                    f'{device} - Error when connecting to device: {error}')
        else:
            logging.info(
                f'{device} - Current config found. Comparing with current running config.')
            # Load the config from the "current" folder
            current_config_file = open(
                current_dir + f"{device}.txt", "r")
            # Get running config from device
            logging.info(f'{device} - Getting running config')
            try:
                output = None
                device_connection = ConnectHandler(
                    device_type='cisco_ios', ip=device, username=DEVICE_USERNAME, password=DEVICE_PASSWORD)
                output = device_connection.send_command("show run")
                file_write = open(
                    configs_dir + f"{device}.txt", "w")
                file_write.write(output)
                file_write.close()
                device_connection.disconnect()
            except NetmikoAuthenticationException:
                logging.warning(
                    f'Unable to login with {DEVICE_USERNAME} user.')
            except Exception as error:
                logging.error(
                    f'{device} - Error when connecting to device: {error}')
            logging.info(f'{device} - Checking for differences...')
            # Check the two for differences
            running_config_file = open(
                configs_dir + f"{device}.txt", "r")
            diff = list(difflib.unified_diff(
                current_config_file.readlines(), running_config_file.readlines()))
            current_config_file.close()
            running_config_file.close()
            if len(diff) == 0:
                logging.info(f'{device} - No changes since last check')
                os.remove(configs_dir + f"{device}.txt")
            else:
                logging.warning(
                    f'{device} - CHANGES DETECTED! Generating changelog')
                current_config_file = open(
                    current_dir + f"{device}.txt", "r")
                running_config_file = open(
                    configs_dir + f"{device}.txt", "r")
                # Create changelog file in "changelog" folder
                diff_html = difflib.HtmlDiff().make_file(current_config_file.readlines(),
                                                         running_config_file.readlines())
                logging.info(
                    f'{device} - Saving changelog to "{changelog_dir}{device}/"')
                if not os.path.exists(changelog_dir + f"{device}"):
                    os.mkdir(changelog_dir + f"{device}")
                diff_html_file_path = changelog_dir + \
                    f"{device}/{device}_{date}.html"
                diff_html_file = open(
                    diff_html_file_path, "w")
                diff_html_file.write(diff_html)
                current_config_file.close()
                running_config_file.close()
                diff_html_file.close()
                # Save running config to "current" folder and move previous config to "archive" folder
                logging.info(
                    f'{device} Saving current running config to "current" folder and moving old version to "archive" folder')
                if not os.path.exists(archive_dir + f"{device}"):
                    os.mkdir(archive_dir + f"{device}")
                os.replace(
                    current_dir + f"{device}.txt", archive_dir + f"{device}/{device}_{date}.txt")
                os.replace(configs_dir + f"{device}.txt",
                           current_dir + f"{device}.txt")
logging.info('Beginning folder cleanup')
cleanup_folder(archive_dir, retention_date, RETENTION_FILE_NUMBER)
cleanup_folder(changelog_dir, retention_date, RETENTION_FILE_NUMBER)
cleanup_folder(logs_dir, retention_date)
logging.info('End folder cleanup')
logging.info('End of config change checker')
