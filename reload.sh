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
docker stop $(docker ps -a -q) 2>/dev/null || echo "No hay contenedores que parar."
docker rm $(docker ps -a -q) 2>/dev/null || echo "No hay contenedores que borrar."
docker network prune -f
docker volume prune -f
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
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al generar el bloque génesis del sistema"
  exit 1
fi
echo "****** Contenido de system-genesis-block: ******"
ls -la ./system-genesis-block

# ---- Levantando la red Fabric (contenedores) ----
echo "****** Levantando la red Fabric (contenedores)... ******"
./net-pln.sh up
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al levantar la red con net-pln.sh up"
  exit 1
fi
echo "Esperando a que los contenedores se estabilicen (10s)..."
sleep 10
############## HASTA AQUI TODO IGUAL ##############

# # ---- Generación de Artefactos de Canal ----
# echo "****** Generando bloque génesis del canal del sistema... ******"
# # Asegúrate que FABRIC_CFG_PATH esté correctamente seteado ANTES de este comando
# export FABRIC_CFG_PATH=${PWD}/configtx # O ${PWD}/config si es allí donde está configtx.yaml
# # configtxgen -profile PharmaLedgerOrdererGenesis -outputBlock ./system-genesis-block/genesis.block -channelID system-channel
# configtxgen -profile PharmaLedgerChannel -outputBlock ./channel-artifacts/plnchannel.block -channelID plnchannel

# if [ $? -ne 0 ]; then
#   echo "ERROR: Fallo al generar el bloque génesis del sistema"
#   exit 1
# fi
# echo "****** Contenido de system-genesis-block: ******"
# ls -la ./system-genesis-block

# ---- Levantando la red Fabric (contenedores) ----
echo "****** Levantando la red Fabric (contenedores)... ******"
./net-pln.sh up
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al levantar la red con net-pln.sh up"
  exit 1
fi
echo "Esperando a que los contenedores se estabilicen (10s)..."
sleep 10

# ---- Crear y Unir Canal de Aplicación (Usando script dedicado) ----
echo "****** Creando y uniendo canal de aplicación ${CHANNEL_NAME} via script... ******"
# Asegúrate que FABRIC_CFG_PATH esté correcto para createChannel.sh si lo necesita internamente
export FABRIC_CFG_PATH=${PWD}/configtx # O ${PWD}/config

./scripts/createChannel.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al crear/unir el canal de aplicación usando createChannel.sh"
  exit 1
fi
echo "****** Canal de aplicación ${CHANNEL_NAME} creado y unido ******"
echo "****** Contenido de channel-artifacts: ******"
ls -la ./channel-artifacts # Verifica que plnchannel.block se haya creado
sleep 5

# ---- Verificar Canales en Peers ----
echo "****** Verificando canales en peer0.org1 ******"
export CORE_PEER_LOCALMSPID=$ORG1_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG1_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_PEER0_TLS_ROOTCERT
export CORE_PEER_TLS_ENABLED=true
export FABRIC_CFG_PATH=${PWD}/config
peer channel list

echo "****** Verificando canales en peer0.org2 ******"
export CORE_PEER_LOCALMSPID=$ORG2_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_PEER0_TLS_ROOTCERT
export CORE_PEER_TLS_ENABLED=true
export FABRIC_CFG_PATH=${PWD}/config
peer channel list

echo "****** Verificando canales en peer0.org3 ******"
export CORE_PEER_LOCALMSPID=$ORG3_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG3_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:11051
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG3_PEER0_TLS_ROOTCERT
export CORE_PEER_TLS_ENABLED=true
export FABRIC_CFG_PATH=${PWD}/config
peer channel list

# ---- Desplegar Smart Contract ----
./net-pln.sh deploySmartContract

# ---- Invocaciones de Chaincode ----
peer lifecycle chaincode queryinstalled
./net-pln.sh invoke equipment GlobalEquipmentCorp 2000.001 e360-Ventilator GlobalEquipmentCorp
./net-pln.sh invoke query 2000.001
./net-pln.sh invoke wholesaler 2000.001 GlobalWholesalerCorp
sleep 2
./net-pln.sh invoke pharmacy 2000.001 PharmacyCorp
sleep 2
./net-pln.sh invoke queryHistory 2000.001

exit 0