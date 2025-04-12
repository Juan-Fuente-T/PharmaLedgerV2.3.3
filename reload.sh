# Script para reiniciar la red de Hyperledger Fabric y realizar tareas de limpieza y configuración.

# Instalar NVM y Node.js
nvm install 14.21.3
nvm use 14.21.3
nvm alias default 14

# Instalar jq
# sudo apt-get install jq -y

#!/bin/bash

# Script para reiniciar la red de Hyperledger Fabric y realizar tareas de limpieza y configuración.

# ---- Configuración ----
export FABRIC_CFG_PATH=${PWD}/configtx
export PATH=${PWD}/../bin:${PWD}:$PATH
# export IMAGE_TAG=2.3.3
echo "****** FABRIC_CFG_PATH is set to: ${FABRIC_CFG_PATH} ******"

# Variables reutilizables
# export CHANNEL_NAME="plnchannel"
export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/example.com/users/Admin@example.com/tls/client.crt
export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/example.com/users/Admin@example.com/tls/client.key
# export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt # O la del Admin si es distinta
# export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key # O la del Admin si es distinta
export ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# Variables específicas de Org1
export ORG1_MSP="Org1MSP"
export ORG1_PEER0_PORT="7051"
export ORG1_ADMIN_MSP_PATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export ORG1_PEER0_TLS_ROOTCERT=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

# Variables específicas de Org2
export ORG2_MSP="Org2MSP"
export ORG2_PEER0_PORT="9051"
export ORG2_ADMIN_MSP_PATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export ORG2_PEER0_TLS_ROOTCERT=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

# Variables específicas de Org3
export ORG3_MSP="Org3MSP"
export ORG3_PEER0_PORT="11051"
export ORG3_ADMIN_MSP_PATH=${PWD}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
export ORG3_PEER0_TLS_ROOTCERT=${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt

# ---- Limpieza Profunda ----
echo "****** Limpiando entorno anterior... ******"
sudo -v
./net-pln.sh down || echo "Fallo al bajar la red (puede que no estuviera arriba)."
# docker stop $(docker ps -a -q) 2>/dev/null || echo "No hay contenedores que parar."
# docker rm $(docker ps -a -q) 2>/dev/null || echo "No hay contenedores que borrar."
# docker network prune -f
# docker volume prune -f
# # ---- Reconstrucción de Imágenes de Apps ----
# echo "****** Reconstruyendo imágenes de las aplicaciones si es necesario... ******"
# docker-compose -f docker/docker-compose-pln-net.yaml build --no-cache manufacturer-app wholesaler-app pharmacy-app
sudo rm -rf ./organizations/peerOrganizations
sudo rm -rf ./organizations/ordererOrganizations
sudo rm -rf ./wallet
sudo rm -rf ./system-genesis-block
sudo rm -rf ./channel-artifacts/*
echo "****** Limpieza completada ******"

# ---- Generación de Artefactos ----
echo "****** Generando artefactos criptográficos... ******"
mkdir -p ./organizations/peerOrganizations
mkdir -p ./organizations/ordererOrganizations
mkdir -p ./wallet
mkdir -p ./system-genesis-block
mkdir -p ./channel-artifacts

cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-org3.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output=organizations

echo "****** Generando CCPs ******"
chmod +x ./organizations/ccp-generate.sh
./organizations/ccp-generate.sh

docker volume create genesis_volume || echo "El volumen ya existía."
docker run --rm -v genesis_volume:/data -v $(pwd)/system-genesis-block:/source alpine sh -c "cp /source/genesis.block /data/genesis.block"
# Verifica que está dentro (opcional)
docker run --rm -v genesis_volume:/data alpine ls -la /data

# Preparación opcional para Hyperledger Explorer (descomentar si se usa)
echo "****** Configurando Hyperledger Explorer wallet... ******"
ADMIN_KEY_FILE=$(find ./organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/ -name '*_sk' -type f -print -quit)
if [ -z "$ADMIN_KEY_FILE" ]; then
  echo "ERROR: No se encontró el archivo de clave privada para Admin@org1.example.com"
  exit 1
fi
mkdir -p ./wallet/admin
cp "$ADMIN_KEY_FILE" ./wallet/admin/private_key
cp ./organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/Admin@org1.example.com-cert.pem ./wallet/admin/certificate

# ---- Generación de Artefactos de Canal ----
echo "****** Generando bloque génesis del canal del sistema... ******"
configtxgen -profile PharmaLedgerOrdererGenesis -outputBlock ./system-genesis-block/genesis.block -channelID system-channel 
echo "****** Contenido de system-genesis-block: ******"
ls -la ./system-genesis-block

# ---- Levantando la red Fabric (contenedores) ----
echo "****** Levantando la red Fabric (contenedores)... ******"
./net-pln.sh up
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al levantar la red con net-pln.sh up"
  exit 1
fi
echo "****** Red levantada, esperando 30 segundos para estabilización completa del Orderer... ******"
sleep 30


# ---- Crear y Unir Canal de Aplicación (Usando script dedicado) ----
echo "****** Creando canal de aplicación ${CHANNEL_NAME} via script... ******"
export FABRIC_CFG_PATH=${PWD}/configtx # O ${PWD}/config
./scripts/createChannel.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al crear el canal de aplicación usando createChannel.sh"
  exit 1
fi
sleep 5


# # ---- Generar Bloque Génesis del Canal de Aplicación ----
# echo "****** Generando bloque génesis del canal ${CHANNEL_NAME}... ******"
# configtxgen -profile PharmaLedgerChannel -outputBlock ./channel-artifacts/plnchannel.block -channelID plnchannel

# ---- Unir Orderer al Canal de Aplicación ----
# echo "****** Haciendo que Orderer se una al canal ${CHANNEL_NAME}... ******"
# osnadmin channel join --channelID plnchannel --config-block ./channel-artifacts/plnchannel.block -o localhost:7053 --ca-file "${ORDERER_CA}" --client-cert "${ORDERER_ADMIN_TLS_SIGN_CERT}" --client-key "${ORDERER_ADMIN_TLS_PRIVATE_KEY}"
# if [ $? -ne 0 ]; then
#   echo "ERROR: Fallo al unir el orderer al canal ${CHANNEL_NAME}"
#   exit 1
# fi
# echo "****** Orderer unido al canal ${CHANNEL_NAME} ******"
# echo "****** Contenido de channel-artifacts: ******"
# ls -la ./channel-artifacts
# sleep 5

# ---- Unir Peers al Canal ----
echo "****** Uniendo peer0.org1 al canal ${CHANNEL_NAME}... ******"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=$ORG1_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG1_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:${ORG1_PEER0_PORT}
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_PEER0_TLS_ROOTCERT
export FABRIC_CFG_PATH=${PWD}/config
for i in $(seq 1 $ATTEMPTS); do
    peer channel join -b ./channel-artifacts/plnchannel.block
    if [ $? -eq 0 ]; then
        echo "Peer unido al canal después de $i intentos."
        break
    fi
    echo "Fallo al unir el peer al canal. Intentando de nuevo en 3 segundos..."
    sleep 3
done
if [ $? -ne 0 ]; then
    echo "ERROR: Fallo al unir el peer al canal después de $ATTEMPTS intentos."
    exit 1
fi
sleep 3

echo "****** Uniendo peer0.org2 al canal ${CHANNEL_NAME}... ******"
export CORE_PEER_LOCALMSPID=$ORG2_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:${ORG2_PEER0_PORT}
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_PEER0_TLS_ROOTCERT
export FABRIC_CFG_PATH=${PWD}/config
for i in $(seq 1 $ATTEMPTS); do
    peer channel join -b ./channel-artifacts/plnchannel.block
    if [ $? -eq 0 ]; then
        echo "Peer unido al canal después de $i intentos."
        break
    fi
    echo "Fallo al unir el peer al canal. Intentando de nuevo en 3 segundos..."
    sleep 3
done
if [ $? -ne 0 ]; then
    echo "ERROR: Fallo al unir el peer al canal después de $ATTEMPTS intentos."
    exit 1
fi
sleep 3

echo "****** Uniendo peer0.org3 al canal ${CHANNEL_NAME}... ******"
export CORE_PEER_LOCALMSPID=$ORG3_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG3_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:${ORG3_PEER0_PORT}
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG3_PEER0_TLS_ROOTCERT
export FABRIC_CFG_PATH=${PWD}/config
for i in $(seq 1 $ATTEMPTS); do
    peer channel join -b ./channel-artifacts/plnchannel.block
    if [ $? -eq 0 ]; then
        echo "Peer unido al canal después de $i intentos."
        break
    fi
    echo "Fallo al unir el peer al canal. Intentando de nuevo en 3 segundos..."
    sleep 3
done
if [ $? -ne 0 ]; then
    echo "ERROR: Fallo al unir el peer al canal después de $ATTEMPTS intentos."
    exit 1
fi

# ---- Verificar Canales en Peers ----
echo "****** Verificando canales en peer0.org1 ******"
export CORE_PEER_LOCALMSPID=$ORG1_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG1_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_PEER0_TLS_ROOTCERT
peer channel list

echo "****** Verificando canales en peer0.org2 ******"
export CORE_PEER_LOCALMSPID=$ORG2_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_PEER0_TLS_ROOTCERT
peer channel list

echo "****** Verificando canales en peer0.org3 ******"
export CORE_PEER_LOCALMSPID=$ORG3_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG3_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:11051
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG3_PEER0_TLS_ROOTCERT
peer channel list

# ---- Desplegar Smart Contract ----
./net-pln.sh deploySmartContract

# ---- Invocaciones de Chaincode ----
export FABRIC_CFG_PATH=${PWD}/config
peer lifecycle chaincode queryinstalled
./net-pln.sh invoke equipment GlobalEquipmentCorp 2000.001 e360-Ventilator GlobalEquipmentCorp
./net-pln.sh invoke query 2000.001
./net-pln.sh invoke wholesaler 2000.001 GlobalWholesalerCorp
sleep 2
./net-pln.sh invoke pharmacy 2000.001 PharmacyCorp
sleep 2
./net-pln.sh invoke queryHistory 2000.001

exit 0