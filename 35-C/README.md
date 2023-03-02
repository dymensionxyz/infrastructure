
# Run env on AWS
## Prepare servers
```
sudo apt update
sudo apt install git jq make gcc -y
wget https://go.dev/dl/go1.18.10.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.18.10.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bashrc
source ~/.bashrc


ulimit -n 8192


mkdir dymension && cd dymension
```


The `aws.env` contains all the ENV variables that need to be overwritten:
```
cp testnet.env ~/dymension/aws.env
```
modify needed values in case needed (e.g set unique CHAIN_ID)


## Server 1 (hub validator 1)
```
git clone https://github.com/dymensionxyz/dymension.git
cd dymension
git checkout v0.2.0-beta
make install

set -a
source ~/dymension/aws.env
set +a
sh scripts/setup_local.sh
```

copy genesis from server 1 to a local directory
```
wget https://raw.githubusercontent.com/dymensionxyz/testnets/main/dymension-hub/35-C/genesis.json -O ~/.dymension/config/genesis.json
```

Set service and run
```
sudo vi /usr/lib/systemd/system/hub.service

sudo systemctl daemon-reload
sudo systemctl enable hub
sudo systemctl start hub && journalctl -f -u hub
```

## Server 2 (hub validator 2)
```
git clone https://github.com/dymensionxyz/dymension.git
cd dymension
git checkout v0.2.0-beta
make install

set -a
source ~/dymension/aws.env
set +a
sh scripts/setup_local.sh
```

copy genesis file to server2
```
curl -s https://raw.githubusercontent.com/dymensionxyz/infrastructure/1fbe5aa772dbe7788a3d0b9b7a0368da4d4d3dcb/AWS/genesis.json > ~/.dymension/config/genesis.json

```

check the address of this account 
```
dymd keys show -a local-user --keyring-backend test
```
and fund it on server1:
```
    dymd tx bank send $(dymd keys show -a local-user --keyring-backend test) XXXXX 10000000000udym --keyring-backend test
```

Set service and run
```
cp hub.service /usr/lib/systemd/system

sudo systemctl daemon-reload
sudo systemctl enable hub
sudo systemctl start hub

journalctl -f -u hub
```

### Make the node as validator
Create a validator on node 2 as well
```
dymd tx staking create-validator \
  --amount 1000000udym \
  --commission-max-change-rate "0.1" \
  --commission-max-rate "0.20" \
  --commission-rate "0.1" \
  --min-self-delegation "1" \
  --details "validators write bios too" \
  --pubkey=$(dymd tendermint show-validator) \
  --moniker "2ndmoniker" \
  --chain-id "local-testnet" \
  --gas-prices 0.025udym \
  --from local-user \
  --keyring-backend test
```



## Server3 (rollapp sequencer)
```
git clone https://github.com/dymensionxyz/dymension.git
cd dymension
git checkout v0.2.0-beta
make install
cd ..


git clone https://github.com/dymensionxyz/dymension-rdk.git
cd dymension-rdk
make install

set -a
source ~/dymension/aws.env
set +a

sh scripts/init_rollapp.sh
sh scripts/register_rollapp_to_hub.sh
sh scripts/register_sequencer_to_hub.sh
```

Set service and run
```
cp rollapp.service /usr/lib/systemd/system

mkdir ~/.rollapp/log
touch ~/.rollapp/log/rollapp.log


sudo systemctl daemon-reload
sudo systemctl enable rollapp
sudo systemctl start rollapp && journalctl -f -u rollapp
```

### To run the relayer:
Download and install

```
git clone https://github.com/dymensionxyz/relayer.git
cd relayer
make install
cd ..
```


Setup and run:

```
set -a
source ~/dymension/aws.env
set +a
sh scripts/setup_ibc.sh

cp relayer.service /usr/lib/systemd/system

sudo systemctl daemon-reload
sudo systemctl enable relayer
sudo systemctl start relayer

sudo systemctl start relayer && journalctl -f -u relayer
```
