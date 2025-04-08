# Instalar NVM y Node.js
nvm install 16.20.2
nvm use 16.20.2
nvm alias default 16

# Instalar jq
sudo apt-get install jq -y

# Configuración del entorno
export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export PATH=$PATH:$(pwd)/bin

# Bajar la red y limpiar contenedores
./net-pln.sh down
docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q) 2>/dev/null
docker volume prune --all -f
docker network prune -f

# Eliminar datos antiguos
sudo rm -rf organizations/peerOrganizations
sudo rm -rf organizations/ordererOrganizations
rm -rf channel-artifacts/
mkdir channel-artifacts

# Generar certificados
# cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output=“organizations”
# cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output=“organizations”
# cryptogen generate --config=./organizations/cryptogen/crypto-config-org3.yaml --output=“organizations”
# cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output=“organizations”
cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-org3.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output=organizations

./organizations/ccp-generate.sh

export FABRIC_CFG_PATH=${PWD}/configtx
# configtxgen -profile PharmaLedgerOrdererGenesis -channelID system-channel -outputBlock ./system-genesis-block/genesis.block
configtxgen -profile PharmaLedgerChannel -outputBlock ./channel-artifacts/plnchannel.block -channelID plnchannel

./net-pln.sh up
# ./net-pln.sh monitor-up

export FABRIC_CFG_PATH=${PWD}/configtx
./net-pln.sh createChannel

# cd pharma-ledger-network/organizations/manufacturer/contract
# npm install

export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=$PWD/config/

# ######  PEER0.ORG1.EXAMPLE.COM  ######
export CORE_PEER_TLS_ENABLED=true
# Ruta al certificado TLS para peer0.org1.example.com
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
# MSP de la organización para peer0.org1.example.com
# export CORE_PEER_LOCALMSPID=“Org1MSP”
export CORE_PEER_LOCALMSPID=Org1MSP
# Ruta al certificado raíz TLS
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG1_CA
# Ruta al directorio MSP de Admin de org1 (usuarios Admin)
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
# Dirección del peer (puerto de peer0.org1.example.com)
export CORE_PEER_ADDRESS=localhost:7051
echo -e “\e[1;32m”
echo -e “┌──────────────────────────────────────────────────────────────────────────────┐”
echo -e “│PEER0.ORG1.EXAMPLE.COM : peer channel list                                    │”
echo -e “└──────────────────────────────────────────────────────────────────────────────┘\e[0m”
echo -e “”
peer channel list
# ######  PEER0.ORG2.EXAMPLE.COM  ######
export CORE_PEER_TLS_ENABLED=true
# Ruta al certificado TLS para peer0.org2.example.com
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
# MSP de la organización para peer0.org2.example.com
# export CORE_PEER_LOCALMSPID=“Org2MSP”
export CORE_PEER_LOCALMSPID=Org2MSP
# Ruta al certificado raíz TLS
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG2_CA
# Ruta al directorio MSP de Admin de org2 (usuarios Admin)
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
# Dirección del peer (puerto de peer0.org1.example.com)
export CORE_PEER_ADDRESS=localhost:9051
echo -e “\e[1;32m”
echo -e “┌──────────────────────────────────────────────────────────────────────────────┐”
echo -e “│PEER0.ORG2.EXAMPLE.COM : peer channel list                                    │”
echo -e “└──────────────────────────────────────────────────────────────────────────────┘\e[0m”
echo -e “”
peer channel list
# ######  PEER0.ORG3.EXAMPLE.COM  ######
export CORE_PEER_TLS_ENABLED=true
# Ruta al certificado TLS para peer0.org3.example.com
export PEER0_ORG3_CA=${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt
# MSP de la organización para peer0.org3.example.com
# export CORE_PEER_LOCALMSPID=“Org3MSP”
export CORE_PEER_LOCALMSPID=Org3MSP
# Ruta al certificado raíz TLS
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG3_CA
# Ruta al directorio MSP de Admin de org3 (usuarios Admin)
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
# Dirección del peer (puerto de peer0.org3.example.com)
export CORE_PEER_ADDRESS=localhost:11051
echo -e “\e[1;32m”
echo -e “┌──────────────────────────────────────────────────────────────────────────────┐”
echo -e “│PEER0.ORG3.EXAMPLE.COM : peer channel list                                    │”
echo -e “└──────────────────────────────────────────────────────────────────────────────┘\e[0m”
echo -e “”
peer channel list

./net-pln.sh deploySmartContract

peer lifecycle chaincode queryinstalled

./net-pln.sh invoke equipment GlobalEquipmentCorp 2000.001 e360-Ventilator GlobalEquipmentCorp
./net-pln.sh invoke query 2000.001
./net-pln.sh invoke wholesaler 2000.001 GlobalWholesalerCorp
./net-pln.sh invoke pharmacy 2000.001 PharmacyCorp
./net-pln.sh invoke queryHistory 2000.001

# Configuración para cada Peer
# declare -A PEERS=(
#     ["Org1"]="7051"
#     ["Org2"]="9051"
#     ["Org3"]="11051"
# )

# for ORG in "${!PEERS[@]}"; do
#     export CORE_PEER_TLS_ENABLED=true
#     export PEER_CA=${PWD}/organizations/peerOrganizations/org${ORG}.example.com/peers/peer0.org${ORG}.example.com/tls/ca.crt
#     export CORE_PEER_LOCALMSPID="Org${ORG}MSP"
#     export CORE_PEER_TLS_ROOTCERT_FILE=$PEER_CA
#     export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org${ORG}.example.com/users/Admin@org${ORG}.example.com/msp
#     export CORE_PEER_ADDRESS=localhost:${PEERS[$ORG]}

#     echo -e "\e[1;32m"
#     echo -e "┌──────────────────────────────────────────────────────────────┐"
#     echo -e "│ PEER0.ORG${ORG}.EXAMPLE.COM : peer channel list              │"
#     echo -e "└──────────────────────────────────────────────────────────────┘\e[0m"
    
#     peer channel list
# done

# Desplegar Smart Contract
# ./net-pln.sh deploySmartContract
# peer lifecycle chaincode queryinstalled

# Invocaciones
# ./net-pln.sh invoke equipment GlobalEquipmentCorp 2000.001 e360-Ventilator GlobalEquipmentCorp
# ./net-pln.sh invoke query 2000.001
# ./net-pln.sh invoke wholesaler 2000.001 GlobalWholesalerCorp
# ./net-pln.sh invoke pharmacy 2000.001 PharmacyCorp
# ./net-pln.sh invoke queryHistory 2000.001