
# Run env on AWS

## OS and architecture

The guide assumes Ubuntu, 22.04 LTS, amd64 architecture.

## Environment Installation

```
sudo apt update -y 
sudo apt install -y sed jq make gcc
mkdir code && cd code
```

### Install go 1.18.4

ver="1.18.4"
cd $HOME
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"

#### Add go to path

echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile

#### Make sure go is installed

go version

## Server 1 (hub validator 1)

### Config the node 

```
git clone https://github.com/dymensionxyz/infrastructure.git
```

Copy `aws.env` and overwrite all relavant variabales inside:

```
cp $HOME/code/infrastructure/AWS/aws.env $HOME/code/aws.env
```

### Install dymd

```
git clone https://github.com/dymensionxyz/dymension.git --branch <tag_name> $HOME/code/dymension
cd $HOME/code/dymension
make install
# link to /usr/local/bin so that the service can find it
sudo ln -s ~/go/bin/dymd /usr/local/bin/
```

### Setup the node

```
set -a
source $HOME/code/aws.env
sh $HOME/code/dymension/scripts/setup_local.sh
```

### Run the node

Change the `external_address` field in the `config.toml` file to the public IP address of the server.
The address should be of the form `tcp://<ip-address>:26656` where ip address should be the instance Public IPv4 DNS.

```
vim ~/.dymension/config/config.toml
```

Set the service and run

```
sudo systemctl link $HOME/code/infrastructure/AWS/hub.service

sudo systemctl daemon-reload
sudo systemctl enable hub
sudo systemctl start hub
```

Update the log rotation to rotate every 10GB
```
sudo sed -i 's/daily/size 10G/' /etc/logrotate.d/rsyslog
sudo systemctl restart syslog
```

## Server 2 (hub validator 2)

Follow the Envirnment Installation section above

### Install dymd

```
git clone https://github.com/dymensionxyz/dymension.git --branch <tag_name> $HOME/code/dymension
cd $HOME/code/dymension
make install
# link to /usr/local/bin so that the service can find it
sudo ln -s ~/go/bin/dymd /usr/local/bin/
```

### Setup the node

git clone https://github.com/dymensionxyz/infrastructure.git $HOME/code/infrastructure

```
```

Copy `aws.env` and overwrite all relavant variabales inside and specifically set the HUB_PEERS to the address of server 1:

```
cp $HOME/code/infrastructure/AWS/aws.env $HOME/code/aws.env && vim $HOME/code/aws.env
```

Run the node setup script.
```
set -a
source $HOME/code/aws.env
sh $HOME/code/dymension/scripts/setup_local.sh
```

### Config the node 


copy genesis from server 1. From your local machine where $SERVER1 and $SERVER2 are the public IP addresses of the servers:

```
scp ubuntu@$SERVER1:/home/ubuntu/.dymension/config/genesis.json . && scp ./genesis.json ubuntu@$SERVER2:/home/ubuntu/.dymension/config/genesis.json
```

### Run the node

Change the `external_address` field in the `config.toml` file to the public IP address of the server.
The address should be of the form `tcp://<ip-address>:26656`
```
vim ~/.dymension/config/config.toml
```

Set the service and run. Note that the security group of the network should allow traffic 26656.

```
sudo systemctl link $HOME/code/infrastructure/AWS/hub.service

sudo systemctl daemon-reload
sudo systemctl enable hub
sudo systemctl start hub
```

Incase the node cant connect to peers make sure all network security requirements are met.

Update the log rotation to rotate every 10GB
```
sudo sed -i 's/daily/size 10G/' /etc/logrotate.d/rsyslog
sudo systemctl restart syslog
```



### Make the node as validator

check the address of this account

```
dymd keys show -a local-user --keyring-backend test
```

and fund it by running the following command on server1. Make sure to replace <server-2-address> with the address of server 2 you got from the previous command

```
    dymd tx bank send $(dymd keys show -a local-user --keyring-backend test) <server-2-address> 10000000000udym --keyring-backend test --broadcast-mode block 
```

Create a validator on node 2 as well

```
source $HOME/code/aws.env

dymd tx staking create-validator \
  --amount 1000000udym \
  --commission-max-change-rate "0.1" \
  --commission-max-rate "0.20" \
  --commission-rate "0.1" \
  --min-self-delegation "1" \
  --details "validators write bios too" \
  --pubkey=$(dymd tendermint show-validator) \
  --moniker "$MONIKER_NAME" \
  --chain-id "$CHAIN_ID" \
  --gas-prices 0.025udym \
  --from local-user \
  --keyring-backend test \
  --broadcast-mode block 
```

## Server3 (rollapp sequencer)

### Install binaries

Install dymd. Make sure to replace <tag_name> with the relevant tag name.
```
git clone https://github.com/dymensionxyz/dymension.git --branch <tag_name> $HOME/code/dymension
cd $HOME/code/dymension
make install
sudo ln -s ~/go/bin/dymd /usr/local/bin/
```

Install relayer. Make sure to replace <tag_name> with the relevant tag/branch name.
```
git clone https://github.com/dymensionxyz/dymension-relayer.git --branch <tag_name> $HOME/code/relayer
cd $HOME/code/relayer
make install
sudo ln -s ~/go/bin/rly /usr/local/bin/
```

Install the RDK. Make sure to replace <tag_name> with the relevant tag/branch name.
```
git clone https://github.com/dymensionxyz/dymension-rdk.git --branch <tag_name> $HOME/code/dymension-rdk
cd $HOME/code/dymension-rdk
make install
sudo ln -s ~/go/bin/rollappd /usr/local/bin/
```

### Run a DA light client and fund it 

follow the instructions on how to run a [DA light client](https://docs.celestia.org/nodes/light-node/)

### Setup the node


```
git clone https://github.com/dymensionxyz/infrastructure.git $HOME/code/infrastructure
```

Copy `aws.env` and overwrite all relavant variabales inside and specifically set the HUB_PEERS to the address of server 1:

```
cp $HOME/code/infrastructure/AWS/aws.env $HOME/code/aws.env && vim $HOME/code/aws.env
```

Setup the sequencer node and register it to the hub.

```
set -a
source $HOME/code/dymension-rdk/scripts/shared.sh
source $HOME/code/aws.env
sh $HOME/code/dymension-rdk/scripts/init_rollapp.sh
sh $HOME/code/dymension-rdk/scripts/settlement/register_rollapp_to_hub.sh
sh $HOME/code/dymension-rdk/scripts/settlement/register_sequencer_to_hub.sh
```

### Run the sequencer

Set the service and run

```
sudo systemctl link $HOME/code/infrastructure/AWS/rollapp.service

sudo systemctl daemon-reload
sudo systemctl enable rollapp
sudo systemctl start rollapp
```

Update the log rotation to rotate every 10GB
```
sudo sed -i 's/daily/size 10G/' /etc/logrotate.d/rsyslog
sudo systemctl restart syslog
```

### Run the relayer

Change the relevant arguments in aws.env file for the relayer

```
vim $HOME/code/aws.env
```

Run the relayer setup script

```
set -a
source $HOME/code/aws.env
sh $HOME/code/dymension-rdk/scripts/ibc/setup_ibc.sh
```



Set the service and run

```

sudo systemctl link $HOME/code/infrastructure/AWS/relayer.service

sudo systemctl daemon-reload
sudo systemctl enable relayer
sudo systemctl start relayer
```
