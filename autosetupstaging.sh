#!/bin/bash

read -p "Please enter the full destination root path (subfolders will be created within here): " destination_root

#destination_root is the root folder and should contain 3 sub directories, Destination, Staging, and Resources
destination_path="${destination_root}/finished"
staging_path="${destination_root}/staging" #The temp directory where things will be downloaded to before processing
resources_path="${destination_root}/resources" #Resources path for files such as other scripts and input files

#Files to be created and used:  
#downloader_script runs the actual downloads, 
#merge_staging_script handles the merge, and 
#staging_batch_input_file_txt is the main input for everything
downloader_script="${resources_path}/downloader.sh"
merge_staging_script="${resources_path}/merge_staging.sh" #file to be used to merge the staging directory into main
staging_batch_input_file_txt="${staging_path}/staging_batch.txt"

#Check to see if destination path exists, and create it if it does not
if [ -d "$destination_path" ]
then
	echo "Directory $destination_path already exists." 
else
	echo "Creating the directory $destination_path"
	mkdir -p $destination_path
fi

#Check to see if staging path exists, and create it if it does not
if [ -d "$staging_path" ]
then
	echo "Directory $staging_path already exists." 
else
	echo "Creating the directory $staging_path"
	mkdir -p $staging_path
fi

#Check to see if resources path exists, and create it if it does not
if [ -d "$resources_path" ]
then
	echo "Directory $resources_path already exists." 
else
	echo "Creating the directory $resources_path"
	mkdir -p $resources_path
fi

#Install Samba
sudo apt-get install samba -y
echo "=================================================================================="
echo "Please provide new password for the user $user for Samba: "
smbpasswd -a $user


###  Append new share to Samba for finished main directory
sudo echo "[Finished Downloads]
Comment = Main directory fed by Staging on $HOSTNAME
Path = $destination_path
Browseable = yes
Writeable = Yes
only guest = no
create mask = 0777
directory mask = 0777
Public = no
Guest ok = no
" >> /etc/samba/smb.conf

#Append new share to Samba for staging directory
sudo echo "[Download Staging]
Comment = Staging directory feeds into Main on $HOSTNAME
Path = $staging_path
Browseable = yes
Writeable = Yes
only guest = no
create mask = 0777
directory mask = 0777
Public = no
Guest ok = no
" >> /etc/samba/smb.conf

#Restart the Samba service to pick up the new config changes
sudo systemctl restart smbd.service


#creating the merge file .sh file script
cat >$merge_staging_script <<merge_file
#!/bin/bash

SOURCE=$staging_path
DESTINATION=$destination_path # Destination can be a local folder or remote

rsync -av --exclude '*.crdownload' \$SOURCE \$DESTINATION

if [ $? -eq 0 ]; then # Only if rsync succeeded
  find "\$SOURCE" -mindepth 1 -delete
else
  echo "RSYNC was not successful!"
  exit 1
fi
merge_file

chmod +x $merge_staging_script #making the merge file executable


echo -n > $staging_batch_input_file_txt  #create the text file which will be used for input to the script
#create the actual downloader .sh file
cat >$downloader_script <<download_and_merge 
#! /bin/bash

SOURCE=$staging_path/
DESTINATION=$destination_path/ # Destination can be a local folder or remote
WGET_INPUT=$staging_batch_input_file_txt

wget -N -c -i \$WGET_INPUT -P \$SOURCE --progress=bar --random-wait --no-use-server-timestamps

if [ $? -eq 0 ]; then
  echo -n > \$WGET_INPUT # Blank input file so downloads arent repeated endlessly
else
  echo "WGET was not successful!"
  exit 1
fi

rsync -av --exclude '*.crdownload' "\$SOURCE" "\$DESTINATION"

if [ $? -eq 0 ]; then # Only if rsync succeeded
  find "\$SOURCE" -mindepth 1 -delete
else
  echo "RSYNC was not successful!"
  exit 1
fi

download_and_merge

chmod +x $downloader_script #make the download script executable

#create cron files in /etc/cron.d to run the scripts on schedule
sudo echo "* 23  * * *   pi  $downloader_script" > /etc/cron.d/nightly_download
sudo echo "*/15 *  * * *   root    $merge_staging_script" > /etc/cron.d/merge_nightly_download

echo "===================================================================================="
echo "Add files to download to: $staging_batch_input_file_txt"
echo "Complete."
