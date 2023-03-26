
# Run env on AWS
## Prepare servers
```
sudo yum update
sudo yum install git go jq make
mkdir dymension && cd dymension
```


The `aws.env` contains all the ENV variables that need to be overwritten:
```
cp aws.env ~/dymension/aws.env
```
modify needed values in case needed (e.g set unique CHAIN_ID)


## Server 1 (hub validator 1)
```
git clone https://github.com/dymensionxyz/dymension.git
cd dymension
make install
sudo ln -s ~/go/bin/dymd /usr/local/bin/

set -a
source ~/dymension/aws.env
sh scripts/setup_local.sh
```

copy genesis from server 1 to a local directory
```
scp ec2-user@$SERVER1:/home/ec2-user/.dymension/config/genesis.json .
```

write the node-id of server1
```
validator1_node_id=dymd tendermint show-node-id
```

Set service and run
```
cp hub.service /usr/lib/systemd/system

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
```
git clone https://github.com/dymensionxyz/dymension.git
cd dymension
make install
sudo ln -s ~/go/bin/dymd /usr/local/bin/

set -a
source ~/dymension/aws.env
sh scripts/setup_local.sh
```

copy genesis from local directory to server2
```
scp genesis.json ec2-user@$SERVER2:/home/ec2-user/.dymension/config/genesis.json
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
```

Update the log rotation to rotate every 10GB
```
sudo sed -i 's/daily/size 10G/' /etc/logrotate.d/rsyslog
sudo systemctl restart syslog
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
make install
sudo ln -s ~/go/bin/dymd /usr/local/bin/
cd ..

git clone https://github.com/dymensionxyz/relayer.git
cd relayer
make install
sudo ln -s ~/go/bin/rly /usr/local/bin/
cd ..

git clone https://github.com/dymensionxyz/dymension-rdk.git
cd dymension-rdk
make install
sudo ln -s ~/go/bin/rollappd /usr/local/bin/

set -a
source ~/dymension/aws.env
sh scripts/init_rollapp.sh
sh scripts/register_rollapp_to_hub.sh
sh scripts/register_sequencer_to_hub.sh
```

Set service and run
```
cp rollapp.service /usr/lib/systemd/system

sudo systemctl daemon-reload
sudo systemctl enable rollapp
sudo systemctl start rollapp
```

Update the log rotation to rotate every 10GB
```
sudo sed -i 's/daily/size 10G/' /etc/logrotate.d/rsyslog
sudo systemctl restart syslog
```

To run the relayer:
```
set -a
source ~/dymension/aws.env
sh scripts/setup_ibc.sh

cp relayer.service /usr/lib/systemd/system

sudo systemctl daemon-reload
sudo systemctl enable relayer
sudo systemctl start relayer
```
