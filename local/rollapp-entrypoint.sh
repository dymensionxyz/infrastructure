#!/bin/bash

set -e

TOKEN_AMOUNT=${TOKEN_AMOUNT:-1000000000000000000000urap}
STAKING_AMOUNT=${STAKING_AMOUNT:-500000000000000000000urap}
KEY_NAME=${KEY_NAME:-local-user}

CHAIN_DIR="$HOME/.rollapp"
CONFIG_DIRECTORY="$CHAIN_DIR/config"
GENESIS_FILE="$CONFIG_DIRECTORY/genesis.json"
TENDERMINT_CONFIG_FILE="$CONFIG_DIRECTORY/config.toml"
CLIENT_CONFIG_FILE="$CONFIG_DIRECTORY/client.toml"
APP_CONFIG_FILE="$CONFIG_DIRECTORY/app.toml"
EXECUTABLE="rollappd"


DENOM='urap'

init_directories() {
    mkdir -p /home/shared/gentx
    mkdir -p /home/shared/peers
}

init_chain() {
    # Init the chain
    $EXECUTABLE init "$MONIKER_NAME" --chain-id="$CHAIN_ID"
    $EXECUTABLE dymint unsafe-reset-all

    # ------------------------------- client config ------------------------------ #
    sed -i'' -e "s/^chain-id *= .*/chain-id = \"$CHAIN_ID\"/" "$CLIENT_CONFIG_FILE"

    # -------------------------------- app config -------------------------------- #
    sed -i'' -e 's/^minimum-gas-prices *= .*/minimum-gas-prices = "0urap"/' "$APP_CONFIG_FILE"

    # ------------------------------ genesis config ------------------------------ #
    sed -i'' -e 's/bond_denom": ".*"/bond_denom": "urap"/' "$GENESIS_FILE"
    sed -i'' -e 's/mint_denom": ".*"/mint_denom": "urap"/' "$GENESIS_FILE"
}

create_genesis() {
    # Import the key for the genesis sequencer as it was funded by the hub already
    echo '12345678' | $EXECUTABLE keys import $KEY_NAME /sequencer-hub.pk --keyring-backend test
    $EXECUTABLE add-genesis-account "$KEY_NAME" "$TOKEN_AMOUNT" --keyring-backend test
    $EXECUTABLE gentx "$KEY_NAME" "$STAKING_AMOUNT" --chain-id "$CHAIN_ID" --keyring-backend test
    $EXECUTABLE collect-gentxs
    cp ~/.rollapp/config/genesis.json /home/shared/gentx/
}

wait_for_genesis() { 
    $EXECUTABLE keys add "$KEY_NAME" --keyring-backend test
    while [ ! -f /home/shared/gentx/genesis.json ]; do
        echo "Waiting for genesis file"
        sleep 1
    done
    # Copy the genesis file to the config directory
    cp /home/shared/gentx/genesis.json ~/.rollapp/config/
}

create_peer_address() {
    PEER_ADDRESS=$($EXECUTABLE dymint show-node-id)@$HOSTNAME:26656
    echo $PEER_ADDRESS > /home/shared/peers/$HOSTNAME
}

wait_for_all_peer_addresses() {
    while [ $(ls /home/shared/peers | wc -l) -ne $NODE_COUNT ]; do
        echo "Waiting for all peers to be present"
        sleep 1
    done
}

add_peers_to_config() {
    # Once all peers are present, add them to the config.toml file
    echo "All peers present. Adding them to config.toml"
    for file in /home/shared/peers/*; do
        echo "Adding $(cat $file) to config.toml"
        sed -i "s/persistent_peers = \"\"/persistent_peers = \"$(cat $file),\"/g" ~/.rollapp/config/config.toml
    done

    # Remove the last comma from the persistent peers
    sed -i "s/,\"/\"/g" ~/.rollapp/config/config.toml
}

main() {
    init_directories
    init_chain
    if [ "$IS_GENESIS_SEQUENCER" = "true" ]; then
        create_genesis
    else
        wait_for_genesis
    fi
    create_peer_address
    wait_for_all_peer_addresses
    add_peers_to_config
    sh /app/scripts/run_rollapp.sh
}

main

