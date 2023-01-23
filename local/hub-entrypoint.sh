#!/bin/bash

set -e

DATA_DIRECTORY="$HOME/.dymension"
CONFIG_DIRECTORY="$DATA_DIRECTORY/config"
GENESIS_FILE="$CONFIG_DIRECTORY/genesis.json"
TENDERMINT_CONFIG_FILE="$CONFIG_DIRECTORY/config.toml"
CLIENT_CONFIG_FILE="$CONFIG_DIRECTORY/client.toml"
APP_CONFIG_FILE="$CONFIG_DIRECTORY/app.toml"
RPC_ADDRESS=${RPC_ADDRESS:-0.0.0.0:26657}
P2P_ADDRESS=${P2P_ADDRESS:-0.0.0.0:26656}
GRPC_ADDRESS=${GRPC_ADDRESS:-0.0.0.0:9090}
GRPC_WEB_ADDRESS=${GRPC_WEB_ADDRESS:-0.0.0.0:9091}

init_directories() {
    mkdir -p /home/shared/gentx
    mkdir -p /home/shared/peers
}

init_chain() {
    # Init the chain
    dymd init "$MONIKER_NAME" --chain-id="$CHAIN_ID"
    dymd tendermint unsafe-reset-all
    dymd keys add "$KEY_NAME" --keyring-backend test
    dymd add-genesis-account "$(dymd keys show "$KEY_NAME" -a --keyring-backend test)" 100000000000udym
    dymd gentx "$KEY_NAME" 100000000udym --chain-id "$CHAIN_ID" --keyring-backend test
    # ---------------------------------------------------------------------------- #
    #                                 update config                                #
    # ----------------------------------------------------------------------------
    sed -i'' -e "/\[rpc\]/,+3 s/laddr *= .*/laddr = \"tcp:\/\/$RPC_ADDRESS\"/" "$TENDERMINT_CONFIG_FILE"
    sed -i'' -e "/\[p2p\]/,+3 s/laddr *= .*/laddr = \"tcp:\/\/$P2P_ADDRESS\"/" "$TENDERMINT_CONFIG_FILE"
    sed -i'' -e "/\[grpc\]/,+6 s/address *= .*/address = \"$GRPC_ADDRESS\"/" "$APP_CONFIG_FILE"
    sed -i'' -e "/\[grpc-web\]/,+7 s/address *= .*/address = \"$GRPC_WEB_ADDRESS\"/" "$APP_CONFIG_FILE"
    sed -i'' -e "s/^chain-id *= .*/chain-id = \"$CHAIN_ID\"/" "$CLIENT_CONFIG_FILE"
    sed -i'' -e "s/^node *= .*/node = \"tcp:\/\/$SETTLEMENT_RPC\"/" "$CLIENT_CONFIG_FILE"
    sed -i'' -e 's/bond_denom": ".*"/bond_denom": "udym"/' "$GENESIS_FILE"
    sed -i'' -e 's/mint_denom": ".*"/mint_denom": "udym"/' "$GENESIS_FILE"
    sed -i'' -e 's/^minimum-gas-prices *= .*/minimum-gas-prices = "0udym"/' "$APP_CONFIG_FILE"
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
        dymd add-genesis-account $VALIDATOR_ACCOUNT 100000000000udym
    done

    echo "Adding sequencer a account to genesis file"
    echo '12345678' | dymd keys import sequencer-a /sequencer-a-hub.pk --keyring-backend test
    dymd add-genesis-account $(dymd keys show sequencer-a -a --keyring-backend test) 100000000000udym

    echo "Adding sequencer b account to genesis file"
    echo '12345678' | dymd keys import sequencer-b /sequencer-b-hub.pk --keyring-backend test
    dymd add-genesis-account $(dymd keys show sequencer-b -a --keyring-backend test) 100000000000udym

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

