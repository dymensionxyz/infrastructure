#!/bin/bash

set -e

DATA_DIRECTORY="$HOME/.dymension"
CONFIG_DIRECTORY="$DATA_DIRECTORY/config"
GENESIS_FILE="$CONFIG_DIRECTORY/genesis.json"

init_directories() {
    mkdir -p /home/shared/gentx
    mkdir -p /home/shared/peers
}

init_chain() {
    # Init the chain
    dymd init "$MONIKER_NAME" --chain-id="$CHAIN_ID"
    dymd tendermint unsafe-reset-all
    dymd keys add "$KEY_NAME" --keyring-backend test
    dymd add-genesis-account "$(dymd keys show "$KEY_NAME" -a --keyring-backend test)" 100000000000dym
    dymd gentx "$KEY_NAME" 100000000dym --chain-id "$CHAIN_ID" --keyring-backend test
    sed -i'' -e 's/bond_denom": ".*"/bond_denom": "dym"/' "$GENESIS_FILE"
    sed -i'' -e 's/mint_denom": ".*"/mint_denom": "dym"/' "$GENESIS_FILE"
}

create_genesis() {
    # Get validator count from environment variable and subtract 1 (genesis validator)
    VALIDATOR_COUNT=$(($VALIDATOR_COUNT - 1))
    # Check if the number of gentx files is equal to the number of validators. If it's not, sleep, else create the genesis file
    while [ $(ls /home/shared/gentx | wc -l) -ne $VALIDATOR_COUNT ]; do
        echo "Waiting for all gentx files to be present"
        sleep 1
    done
    # Iterate over all the gentx files add get the delegator address and add them to the genesis file
    for file in /home/shared/gentx/*.json; do
        VALIDATOR_ACCOUNT=$(cat $file | jq -r '.body.messages[0].delegator_address')
        echo "Adding $VALIDATOR_ACCOUNT to genesis file"
        dymd add-genesis-account $VALIDATOR_ACCOUNT 100000000000dym
    done

    echo "Adding sequencer account to genesis file"
    echo '12345678' | dymd keys import sequencer-1 /sequencer-hub.pk --keyring-backend test
    dymd add-genesis-account $(dymd keys show sequencer-1 -a --keyring-backend test) 100000000000dym

    echo "All accounts added. Creating genesis file and copying to shared volume"
    dymd collect-gentxs --gentx-dir /home/shared/gentx
    cp ~/.dymension/config/genesis.json /home/shared/gentx/
}

wait_for_genesis() { 
    cp ~/.dymension/config/gentx/* /home/shared/gentx/
    # If you're not, wait until the genesis file is present
    while [ ! -f /home/shared/gentx/genesis.json ]; do
        echo "Waiting for genesis file"
        sleep 1
    done
    # Copy the genesis file to the config directory
    cp /home/shared/gentx/genesis.json ~/.dymension/config/
}

create_peer_address() {
    PEER_ADDRESS=$(dymd tendermint show-node-id)@$HOSTNAME:26656
    echo $PEER_ADDRESS > /home/shared/peers/$HOSTNAME
}

wait_for_all_peer_addresses() {
    while [ $(ls /home/shared/peers | wc -l) -ne $VALIDATOR_COUNT ]; do
        echo "Waiting for all peers to be present"
        sleep 1
    done
}

add_peers_to_config() {
    # Once all peers are present, add them to the config.toml file
    echo "All peers present. Adding them to config.toml"
    for file in /home/shared/peers/*; do
        echo "Adding $(cat $file) to config.toml"
        sed -i "s/persistent_peers = \"\"/persistent_peers = \"$(cat $file),\"/g" ~/.dymension/config/config.toml
    done

    # Remove the last comma from the persistent peers
    sed -i "s/,\"/\"/g" ~/.dymension/config/config.toml
}

main() {
    init_directories
    init_chain
    if [ "$IS_GENESIS_VALIDATOR" = "true" ]; then
        create_genesis
    else
        wait_for_genesis
    fi
    create_peer_address
    wait_for_all_peer_addresses
    add_peers_to_config
    dymd start
}

main

