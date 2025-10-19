#Install and get sudo commands out of the way because build and test_build need to be ran as standard user. 

# prerequisites: ensure apt cache is fresh, install git and ansible if missing
if ! command -v git >/dev/null 2>&1 || ! command -v ansible >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y git ansible
fi
#sudo rm /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y build-essential dkms linux-headers-$(uname -r)
sudo /usr/bin/VBoxClient --version  # should print a version like 7.0.20
