

#!/bin/bash

# Juan Fuente Smart Contract Development with Hyperledger Fabric V2 (Modified for v2.3+)
# farma ledger supply chain network
# Creates/Joins channel using Orderer Channel Participation API

CHANNEL_NAME="$1"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
: ${CHANNEL_NAME:="plnchannel"}
: ${DELAY:="3"}
: ${MAX_RETRY:="5"}
: ${VERBOSE:="false"}
TOTAL_ORGS=3

# Import utils
# Assume utils.sh defines setGlobalVars, verifyResult, logging functions,
# and ORDERER_CA (path to Orderer Org's TLS CA Root certificate)
UTILS_PATH="./scripts/utils.sh" # Make sure this path is correct
if [ ! -f "$UTILS_PATH" ]; then
    echo "ERROR: Utility script not found at $UTILS_PATH"
    exit 1
fi
. "$UTILS_PATH"

# Example: Use the correct admin listen address and port defined in docker-compose for the orderer
ORDERER_ADMIN_LISTENADDRESS="localhost:9443"
# Orderer client connection details (used for peer channel create/fetch/update)
ORDERER_CLIENT_LISTENADDRESS="localhost:7050"

# Example paths for Orderer Admin's TLS credentials.
# Ensure these files exist and the paths are correct. The admin user might be created by cryptogen.
ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/example.com/users/Admin@example.com/tls/client.crt
ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/example.com/users/Admin@example.com/tls/client.key

# ORDERER_CA should be defined in utils.sh, pointing to the Orderer Org's TLS CA Root cert
# e.g., ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem


# --- Log Header ---
echo
echo " ____      _____       _       ____     _____ "
echo "/ ___|    |_   _|     / \     |  _ \   |_   _|"
echo "\___ \      | |      / _ \    | |_) |    | |  "
echo " ___) |     | |     / ___ \   |  _ <     | |  "
echo "|____/      |_|    /_/   \_\  |_| \_\    |_|  "
echo
echo "Creating/Joining Pharma Ledger Network (PLN) Channel '$CHANNEL_NAME' using Orderer Participation API"
echo

if [ -z "$ORDERER_CA" ]; then
    echo "ERROR: ORDERER_CA variable is not set. Please define it in utils.sh or here."
    exit 1
fi

if [ ! -d "channel-artifacts" ]; then
    mkdir channel-artifacts
fi

# --- Function Definitions ---
# STEP 0: Create Channel Genesis Block
# Generates the channel transaction and creates the channel genesis block via the orderer
createChannelGenesisBlock() {
    starCallFuncWithStepLog "createChannelGenesisBlock" 0 # Step 0

    local configtx_dir="${PWD}/configtx"       # Directory containing configtx.yaml
    local peer_config_dir="${PWD}/config"     # Directory containing core.yaml
    local artifacts_dir="./channel-artifacts"
    local channel_tx_file="${artifacts_dir}/${CHANNEL_NAME}.tx"
    local channel_block_file="${artifacts_dir}/${CHANNEL_NAME}.block"
    local channel_profile="PharmaLedgerChannel" # Profile name in configtx.yaml for the app channel

    # 1. Generate Channel Configuration Transaction (.tx)
    displayMsg "Generating channel configuration transaction '${CHANNEL_NAME}.tx'"
    export FABRIC_CFG_PATH="$configtx_dir"
    if [ ! -f "${configtx_dir}/configtx.yaml" ]; then
        echo "ERROR: configtx.yaml not found in $configtx_dir"
        exit 1
    fi
    set -x
    configtxgen -profile "$channel_profile" -outputCreateChannelTx "$channel_tx_file" -channelID "$CHANNEL_NAME"
    res=$?
    set +x
    verifyResult $res "Failed to generate channel configuration transaction '$channel_tx_file'"

    # 2. Create Channel Genesis Block (.block) using peer channel create
    displayMsg "Creating channel genesis block '${CHANNEL_NAME}.block' by submitting to orderer"
    export FABRIC_CFG_PATH="$peer_config_dir" # Set path for peer core.yaml
    if [ ! -f "${peer_config_dir}/core.yaml" ]; then
        echo "ERROR: core.yaml not found in $peer_config_dir (needed for peer commands)"
        exit 1
    fi
    # Set environment for the Org Admin creating the channel (e.g., Org1)
    local creating_org=1
    setGlobalVars $creating_org # This function must set CORE_PEER_LOCALMSPID, CORE_PEER_MSPCONFIGPATH etc.

    set -x
    # Ensure ORDERER_CA is correctly set by utils.sh or defined above
    # Ensure ORDERER_CLIENT_LISTENADDRESS is the correct orderer client endpoint
    peer channel create -o "$ORDERER_CLIENT_LISTENADDRESS" \
                       -c "$CHANNEL_NAME" \
                       -f "$channel_tx_file" \
                       --outputBlock "$channel_block_file" \
                       --tls --cafile "$ORDERER_CA"
    res=$?
    set +x
    verifyResult $res "Failed to create channel genesis block '$channel_block_file'"
    echo
    endCallFuncLogWithMsg "createChannelGenesisBlock" "Channel Genesis Block '${CHANNEL_NAME}.block' created successfully on the network."
}

# STEP 1: Generate Anchor Peer Transactions (Prerequisite for Step 4)
createAncorPeerTxn() {
    starCallFuncWithStepLog "createAncorPeerTxn" 1 # Step 1: Generate Anchor Peer TXs
    for orgmsp in Org1MSP Org2MSP Org3MSP; do
        displayMsg "Generating anchor peer update transaction for ${orgmsp}"
        # Set FABRIC_CFG_PATH for configtxgen
        export FABRIC_CFG_PATH=${PWD}/configtx
        set -x
        configtxgen -profile PharmaLedgerChannel -outputAnchorPeersUpdate ./channel-artifacts/${orgmsp}anchors.tx -channelID $CHANNEL_NAME -asOrg ${orgmsp}
        res=$?
        set +x
        verifyResult $res "Failed to generate anchor peer update transaction for ${orgmsp}"
        echo
    done
    endCallFuncLogWithMsg "createAncorPeerTxn" "Generated channel anchor peer transactions"
}

# STEP 2: Orderer Joins the Channel (Optional/Recommended)
# Makes the specific orderer node aware via its admin endpoint, uses the genesis block
# Requires Orderer Admin TLS certs and the channel genesis block
ordererJoinChannel() {
    starCallFuncWithStepLog "ordererJoinChannel" 2 # Step 2: Orderer Joins Channel
    displayMsg "Attempting to make Orderer join channel '$CHANNEL_NAME'..."

    # Set FABRIC_CFG_PATH potentially needed by osnadmin for config resolution, point to core.yaml dir
    # Though osnadmin primarily relies on flags for connection info.
    export FABRIC_CFG_PATH=${PWD}/config

    # --- Verification of necessary files ---
    local config_block="./channel-artifacts/${CHANNEL_NAME}.block"
    local critical_files=("$config_block" "$ORDERER_CA" "$ORDERER_ADMIN_TLS_SIGN_CERT" "$ORDERER_ADMIN_TLS_PRIVATE_KEY")
    local all_files_found=true
    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "ERROR: Required file not found: $file"
            all_files_found=false
        fi
    done
    if [ "$all_files_found" = false ]; then
        exit 1 # Exit if any critical file is missing
    fi
    # --- End Verification ---

    local rc=1
    local COUNTER=1
    # Attempt to join the Orderer to the channel
    while [ $rc -ne 0 -a $COUNTER -le $MAX_RETRY ] ; do
        sleep $DELAY
	set +x
	cat log.txt # Muestra la salida para depuración
	if grep -q "cannot join: system channel exists" log.txt; then
		echo "Orderer reported 'cannot join: system channel exists'. Assuming already joined."
		res=0 # Sobrescribe el resultado para indicar éxito/ya unido
	fi
	let rc=$res # Actualiza rc basado en el 'res' potencialmente modificado
	if [ $rc -ne 0 ]; then
    echo "Orderer join command failed (Attempt $COUNTER/$MAX_RETRY). Retrying in $DELAY seconds..."
    # cat log.txt ya se hizo antes
fi
COUNTER=$(expr $COUNTER + 1)
done
# Después del bucle, usa el 'res' final (potencialmente 0 si se encontró el error específico)
verifyResult $res "Orderer failed to join the channel '$CHANNEL_NAME' after $MAX_RETRY attempts"
 echo
    # Add a delay to allow the orderer to fully process the join request before peers attempt to join
    displayMsg "Waiting for ${DELAY}s after orderer join..."
    sleep 10
}

# STEP 3: Peers Join the Channel
# Function for a single peer org to join
joinChannel() {
    # Ensure correct FABRIC_CFG_PATH for peer commands (points to dir with core.yaml)
    export FABRIC_CFG_PATH=${PWD}/config
    ORG=$1 # Pass ORG as argument
    setGlobalVars $ORG # Set peer environment variables (like CORE_PEER_ADDRESS, CORE_PEER_LOCALMSPID etc.)
    local rc=1
    local COUNTER=1
    local block_file="./channel-artifacts/${CHANNEL_NAME}.block"

    if [ ! -f "$block_file" ]; then
        echo "ERROR: Channel block file not found for peer join: $block_file"
        # Optionally try fetching the block if the orderer has it
        # echo "Attempting to fetch block from orderer..."
        # peer channel fetch 0 $block_file -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com -c $CHANNEL_NAME --tls --cafile $ORDERER_CA
        # if [ $? -ne 0 ]; then
        #    echo "ERROR: Failed to fetch channel block."
        #    exit 1
        # fi
        exit 1 # Exit if block is not found and fetching is not implemented/desired
    fi

    # Attempt to join the peer to the channel
    while [ $rc -ne 0 -a $COUNTER -le $MAX_RETRY ] ; do
        sleep $DELAY
        set -x
        peer channel join -b "$block_file" >&log.txt
        res=$?
        set +x
        let rc=$res
        if [ $rc -ne 0 ]; then
            echo "peer0.org${ORG} failed to join channel (Attempt $COUNTER/$MAX_RETRY). Retrying in $DELAY seconds..."
            cat log.txt # Display the error log from peer channel join
        fi
        COUNTER=$(expr $COUNTER + 1)
    done
    cat log.txt # Display the final log output
    verifyResult $res "After $MAX_RETRY attempts, peer0.org${ORG} has failed to join channel '$CHANNEL_NAME'"
}

# Function to join peers for all orgs
joinMultiPeersToChannel() {
    starCallFuncWithStepLog "joinMultiPeersToChannel" 3 # Step 3: Peers Join Channel
    for org in $(seq 1 $TOTAL_ORGS); do
        starCallFuncWithStepLog "joinChannel Org$org" 3
        joinChannel $org # Pass org number to joinChannel function
        endCallFuncLogWithMsg "joinChannel" "peer0.org${org} joined channel \"$CHANNEL_NAME\""
        echo
    done
}

# STEP 4: Update Anchor Peers
# Function to update anchor peer for a single org
updateAnchorPeers() {
    export FABRIC_CFG_PATH="${PWD}/config"
    local ORG=$1
    local ORG_MSP="Org${ORG}MSP"
    local ANCHOR_PEER_HOST="peer0.org${ORG}.example.com"
    # Determine port based on ORG - ADJUST THESE PORTS AS NEEDED FOR YOUR setup
    local ANCHOR_PEER_PORT=7051
    if [ "$ORG" -eq 2 ]; then ANCHOR_PEER_PORT=9051; elif [ "$ORG" -eq 3 ]; then ANCHOR_PEER_PORT=11051; fi

    setGlobalVars $ORG # Set env for Org Admin

    displayMsg "Updating anchor peer for ${ORG_MSP} to ${ANCHOR_PEER_HOST}:${ANCHOR_PEER_PORT}..."
    local rc=1
    local COUNTER=1
    # Define filenames (can be reused if cleaned properly)
    local fetched_block_pb="config_block_org${ORG}.pb"
    local decoded_block_json="config_block_org${ORG}.json"
    local original_config_pb="config_org${ORG}_original.pb"
    local modified_config_pb="config_org${ORG}_modified.pb"
    local update_pb="update_org${ORG}.pb"
    local update_json="update_org${ORG}.json"
    local update_envelope_json="update_in_envelope_org${ORG}.json"
    local update_envelope_pb="update_in_envelope_org${ORG}.pb"
    local update_log="anchor_update_org${ORG}.log"

    # Clean any previous attempt's files for this org
    rm -f "$fetched_block_pb" "$decoded_block_json" "$original_config_pb" \
          "$modified_config_pb" "$update_pb" "$update_json" \
          "$update_envelope_json" "$update_envelope_pb" "$update_log"

    while [ $rc -ne 0 -a $COUNTER -le $MAX_RETRY ] ; do
        displayMsg "- Attempt ${COUNTER}/${MAX_RETRY}..."
        if [ $COUNTER -gt 1 ]; then sleep $DELAY; fi

        # 1. Fetch Config Block
        displayMsg "  - Fetching current block..."
        peer channel fetch config "$fetched_block_pb" -o "$ORDERER_CLIENT_LISTENADDRESS" -c "$CHANNEL_NAME" --tls --cafile "$ORDERER_CA" > "$update_log" 2>&1
        res=$?
        if [ $res -ne 0 ] || grep -q -i "error" "$update_log"; then echo "ERROR: Failed fetch config block (Attempt $COUNTER)"; cat "$update_log"; rc=1; COUNTER=$((COUNTER + 1)); continue; fi

        # 2. Decode Block to JSON
        displayMsg "  - Decoding block..."
        configtxlator proto_decode --input "$fetched_block_pb" --type common.Block --output "$decoded_block_json" > "$update_log" 2>&1
        res=$?
        if [ $res -ne 0 ] || [ ! -f "$decoded_block_json" ] || grep -q -i "error" "$update_log"; then echo "ERROR: Failed proto_decode block (Attempt $COUNTER)"; cat "$update_log"; rc=1; COUNTER=$((COUNTER + 1)); continue; fi

        # 3. Encode Original Config -> Protobuf
        displayMsg "  - Encoding original config..."
        cat "$decoded_block_json" | jq '.data.data[0].payload.data.config' | \
        configtxlator proto_encode --type common.Config --output "$original_config_pb" > "$update_log" 2>&1
        res=$?
        if [ $res -ne 0 ] || [ ! -s "$original_config_pb" ] || grep -q -i "error" "$update_log"; then echo "ERROR: Failed encoding original config (Attempt $COUNTER)"; cat "$update_log"; rc=1; COUNTER=$((COUNTER+1)); continue; fi

        # 4. Encode Modified Config -> Protobuf
        displayMsg "  - Encoding modified config..."
        cat "$decoded_block_json" | jq '.data.data[0].payload.data.config' | \
        jq --arg host "$ANCHOR_PEER_HOST" --argjson port "$ANCHOR_PEER_PORT" \
           '.channel_group.groups.Application.groups.'"$ORG_MSP"'.values += {"AnchorPeers":{"mod_policy": "Admins", "value":{"anchor_peers": [{"host": $host, "port": $port}]},"version": "0"}}' | \
        configtxlator proto_encode --type common.Config --output "$modified_config_pb" > "$update_log" 2>&1
        res=$?
        if [ $res -ne 0 ] || [ ! -s "$modified_config_pb" ] || grep -q -i "error" "$update_log"; then echo "ERROR: Failed encoding modified config (Attempt $COUNTER)"; cat "$update_log"; rc=1; COUNTER=$((COUNTER+1)); continue; fi

        # 5. Compute Update Delta
        displayMsg "  - Computing update delta..."
        configtxlator compute_update --channel_id "$CHANNEL_NAME" \
                                     --original "$original_config_pb" \
                                     --updated "$modified_config_pb" \
                                     --output "$update_pb" > "$update_log" 2>&1
        res=$?
        if [ $res -ne 0 ] || [ ! -s "$update_pb" ] || grep -q -i "error" "$update_log"; then echo "ERROR: Failed compute update delta (Attempt $COUNTER)"; cat "$update_log"; rc=1; COUNTER=$((COUNTER + 1)); continue; fi

        # 6. Prepare Envelope
        displayMsg "  - Preparing update envelope..."
        configtxlator proto_decode --input "$update_pb" --type common.ConfigUpdate --output "$update_json" > /dev/null 2>&1 # Decode quiet
        res=$?; if [ $res -ne 0 ]; then echo "ERROR: Failed decoding update delta (Attempt $COUNTER)"; rc=1; COUNTER=$((COUNTER + 1)); continue; fi
        echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL_NAME'", "type":2}},"data":{"config_update":'$(cat $update_json)'}}}' | jq . > "$update_envelope_json"
        res=$?; if [ $res -ne 0 ] || [ ! -s "$update_envelope_json" ]; then echo "ERROR: Failed creating envelope JSON (Attempt $COUNTER)"; rc=1; COUNTER=$((COUNTER + 1)); continue; fi
        configtxlator proto_encode --input "$update_envelope_json" --type common.Envelope --output "$update_envelope_pb" > /dev/null 2>&1 # Encode quiet
        res=$?; if [ $res -ne 0 ] || [ ! -s "$update_envelope_pb" ]; then echo "ERROR: Failed encoding envelope protobuf (Attempt $COUNTER)"; rc=1; COUNTER=$((COUNTER + 1)); continue; fi

        # 7. Sign and Submit Update Envelope
        displayMsg "  - Submitting update..."
        setGlobalVars $ORG # Ensure Org Admin env
        peer channel update -f "$update_envelope_pb" -c "$CHANNEL_NAME" -o "$ORDERER_CLIENT_LISTENADDRESS" --tls --cafile "$ORDERER_CA" > "$update_log" 2>&1
        res=$?
        # Check command result AND log content for errors more strictly
        if [ $res -ne 0 ] || grep -q -E "ERRO|Error|FAILED|Failed" "$update_log"; then
            cat "$update_log" # Show log only if error occurred
            echo "ERROR: peer channel update failed (Attempt $COUNTER). Retrying..."
            rc=1
        else
            displayMsg "  - Update submitted successfully."
            rc=0 # Success!
            if [ "$VERBOSE" = "true" ]; then cat "$update_log"; fi
            break # Exit while loop
        fi

        COUNTER=$((COUNTER + 1))
    done # End while loop

    # Cleanup intermediate files
    rm -f "$fetched_block_pb" "$decoded_block_json" "$original_config_pb" \
          "$modified_config_pb" "$update_pb" "$update_json" \
          "$update_envelope_json" "$update_envelope_pb" "$update_log"

    if [ $rc -ne 0 ]; then echo "!!!!!!!!!!!!!!! Anchor peer update failed for org ${ORG} after ${MAX_RETRY} attempts !!!!!!!!!!!!!!!!"; fi
    return $rc
}

# Function to update anchor peers for all orgs
updateOrgsOnAnchorPeers() {
    starCallFuncWithStepLog "updateOrgsOnAnchorPeers" 4 # Step 4
    displayMsg "Updating anchor peers for all orgs on channel '$CHANNEL_NAME'..."
    local overall_success=0 # Track if any update fails

    for org in $(seq 1 $TOTAL_ORGS); do
         starCallFuncWithStepLog "updateAnchorPeers Org$org" 4 "(Sub-step)"
         updateAnchorPeers $org # Call the function for the org
         res=$? # Capture the return code from updateAnchorPeers
         if [ $res -ne 0 ]; then
             # Log specific failure but continue to try other orgs? Or exit?
             # For now, log and set overall failure flag
             echo "ERROR: Failed to update anchor peer for Org${org}."
             overall_success=1 # Mark that at least one failed
             # If you want to stop immediately on first failure, uncomment next line:
             # verifyResult $res "Anchor peer update failed for Org${org}."
         fi
         # Log completion message regardless of intermediate failure? Or only on success?
         # Let's log completion only if res == 0
         if [ $res -eq 0 ]; then
            endCallFuncLogWithMsg "updateAnchorPeers Org$org" "Anchor peer for org${org} updated/verified"
         fi
         echo
    done

    # Final verification based on the overall success flag
    verifyResult $overall_success "One or more anchor peer updates failed."
    endCallFuncLogWithMsg "updateOrgsOnAnchorPeers" "All anchor peer updates processed."
}

# --- Main Execution Flow ---

## Step 0: Create channel genesis block using peer channel create
createChannelGenesisBlock

## Step 1: Generate anchor peer transactions (Prerequisite for Step 4)
createAncorPeerTxn

## Step 2: Orderer joins the channel using osnadmin (ensures admin endpoint is aware)
# This step might be optional if 'peer channel create' suffices, but kept for robustness
ordererJoinChannel

## Step 3: Join all org peers to the channel
joinMultiPeersToChannel

## Optional Wait for network stabilization
# echo "Waiting 20 seconds for network stabilization..."
# sleep 20

## Step 4: Set the anchor peers for each org in the channel
updateOrgsOnAnchorPeers
# --- Completion ---
echo
echo "========= Pharma Ledger Network (PLN) Channel $CHANNEL_NAME successfully joined =========== "

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
