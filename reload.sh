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

# --- Crear Wallet para Explorer ---
echo "****** Creando/Regenerando wallet para Explorer... ******"
WALLET_DIR="./wallet" # Directorio donde Explorer buscará la identidad
ADMIN_CERT_SRC="${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/Admin@org1.example.com-cert.pem"
# Encuentra el archivo _sk dinámicamente por si cambia el hash
ADMIN_KEY_SRC_DIR="${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/"
ADMIN_KEY_SRC=$(find "$ADMIN_KEY_SRC_DIR" -type f -name '*_sk')

# Verifica que los archivos fuente existen (importante, después de cryptogen)
if [ ! -f "$ADMIN_CERT_SRC" ]; then
    echo "ERROR: Certificado fuente de Admin Org1 no encontrado en $ADMIN_CERT_SRC"
    exit 1
fi
if [ -z "$ADMIN_KEY_SRC" ]; then
    echo "ERROR: Clave privada fuente (_sk) de Admin Org1 no encontrada en $ADMIN_KEY_SRC_DIR"
    exit 1
fi
# Asegurarse de que solo hay una clave _sk
if [ $(echo "$ADMIN_KEY_SRC" | wc -l) -ne 1 ]; then
     echo "ERROR: Se encontró más de una clave privada (_sk) en $ADMIN_KEY_SRC_DIR. Limpia el directorio."
     exit 1
fi

# Asegura que el directorio wallet existe (lo crea si rm lo borró)
mkdir -p "$WALLET_DIR"

# Captura los PEM formateados correctamente para JSON usando jq
CERT_PEM_JSON=$(jq -Rs '.' "$ADMIN_CERT_SRC")
KEY_PEM_JSON=$(jq -Rs '.' "$ADMIN_KEY_SRC")

# Crea el archivo admin.id usando las variables (SIN COPIAR/PEGAR MANUALMENTE)
cat << EOF > "${WALLET_DIR}/admin.id"
{
  "credentials": {
    "certificate": ${CERT_PEM_JSON},
    "privateKey": ${KEY_PEM_JSON}
  },
  "mspId": "Org1MSP",
  "type": "X.509",
  "version": 1
}
EOF

# Verifica la creación del archivo
if [ ! -f "${WALLET_DIR}/admin.id" ]; then
    echo "ERROR: Falló la creación de ${WALLET_DIR}/admin.id"
    exit 1
else
    echo "****** Wallet 'admin.id' para Explorer creada/regenerada exitosamente. ******"
fi
# --- Fin Crear Wallet para Explorer ---


echo "****** Generando CCPs ******"
chmod +x ./organizations/ccp-generate.sh
./organizations/ccp-generate.sh

# ---- Generación de Artefactos de Canal ----
echo "****** Generando bloque génesis del canal del sistema... ******"
configtxgen -profile PharmaLedgerOrdererGenesis -outputBlock ./system-genesis-block/genesis.block -channelID system-channel 
echo "****** Contenido de system-genesis-block: ******"
ls -la ./system-genesis-block

# ---- Levantando la red Fabric (contenedores) ----
echo "****** Levantando la red Fabric (contenedores)... ******"
# --- Bloque de Verificación del Genesis Block en Host ---
GENESIS_BLOCK_PATH="./system-genesis-block/genesis.block"
echo "****** Verificando ruta en host ANTES de montar: $GENESIS_BLOCK_PATH ******"

if [ -f "$GENESIS_BLOCK_PATH" ]; then
    # Si existe Y ES un archivo regular
    echo "INFO: La ruta existe y ES un ARCHIVO en el host."
    ls -la "$GENESIS_BLOCK_PATH" # Muestra detalles del archivo
elif [ -d "$GENESIS_BLOCK_PATH" ]; then
    # Si existe PERO ES un directorio
    echo "ERROR FATAL: ¡La ruta existe pero ES UN DIRECTORIO en el host!"
    echo "Contenido del directorio:"
    ls -la ./system-genesis-block/
    exit 1 # Detiene el script ANTES de intentar montar un directorio
else
    # Si no existe
    echo "ERROR FATAL: ¡La ruta $GENESIS_BLOCK_PATH NO EXISTE en el host!"
    echo "Verifica que configtxgen se ejecutó correctamente antes."
    echo "Contenido de ./system-genesis-block/ por si acaso:"
    ls -la ./system-genesis-block/
    exit 1 # Detiene el script
fi
echo "****** Verificación en host OK (es un archivo), intentando levantar red... ******"
# --- Fin Bloque de Verificación -

echo "****** Levantando red... ******"
./net-pln.sh up
echo "Esperando a que los contenedores se estabilicen (10s)..."
sleep 10

# echo "****** Copiando genesis.block DIRECTAMENTE al contenedor Orderer via 'docker cp'... ******"
# docker exec orderer.example.com mkdir -p /var/hyperledger/orderer/genesis
# docker cp ./system-genesis-block/genesis.block orderer.example.com:/var/hyperledger/orderer/genesis/genesis.block

# # Verifica si la copia falló (opcional pero recomendado)
# if [ $? -ne 0 ]; then
#   echo "ERROR: Falló 'docker cp' al copiar el genesis.block al contenedor del Orderer."
#   # exit 1
# else
#   echo "INFO: 'docker cp' completado (código de salida $?)." # Añadido para confirmación
# fi

# # --- NUEVO: VERIFICAR ARCHIVO ANTES DE REINICIAR ---
# echo "****** Verificando archivo DESPUÉS de cp, ANTES de restart: ******"
# docker exec orderer.example.com ls -la /var/hyperledger/orderer/genesis/genesis.block || echo "ERROR: El archivo NO EXISTE según 'docker exec ls' ANTES del restart."

# echo "****** Reiniciando el Orderer para que lea el bloque copiado... ******"
# docker restart orderer.example.com

# echo "****** Esperando después de restart (8s)... ******"
# sleep 8

# # --- NUEVO: VERIFICAR ARCHIVO DESPUÉS DE REINICIAR ---
# echo "****** Verificando archivo DESPUÉS de restart: ******"
# docker exec orderer.example.com ls -la /var/hyperledger/orderer/genesis/genesis.block || echo "ERROR: El archivo NO EXISTE según 'docker exec ls' DESPUÉS del restart."

# echo "****** Verificando logs del Orderer DESPUÉS de 'docker cp' y 'restart'... ******"
# docker logs orderer.example.com | head -n 70


# ---- Unir Orderer al Canal del sistema----
# echo "****** Haciendo que Orderer se una al canal ${CHANNEL_NAME}... ******"
# osnadmin channel join --channelID system-channel --config-block ./system-genesis-block/genesis.block -o localhost:7053 --ca-file "${ORDERER_CA}" --client-cert "${ORDERER_ADMIN_TLS_SIGN_CERT}" --client-key "${ORDERER_ADMIN_TLS_PRIVATE_KEY}"
# echo "****** Variables para el plnChannel ${ORDERER_CA}...${ORDERER_ADMIN_TLS_SIGN_CERT}...${ORDERER_ADMIN_TLS_PRIVATE_KEY} ******"
# osnadmin channel join --channelID plnchannel --config-block ./channel-artifacts/plnchannel.block -o localhost:7053 --ca-file "${ORDERER_CA}"
# osnadmin channel join --channelID ${CHANNEL_NAME} --config-block ./channel-artifacts/${CHANNEL_NAME}.block -o localhost:7053 --ca-file "${ORDERER_CA}"
if [ $? -ne 0 ]; then
  echo "ERROR: Fallo al unir el orderer al canal"
  exit 1
fi
echo "****** Orderer unido al canal ${CHANNEL_NAME} ******"
sleep 5


# ---- Generar Bloque Génesis del Canal de Aplicación ----
echo "****** Generando bloque génesis del canal ${CHANNEL_NAME}... ******"
configtxgen -profile PharmaLedgerChannel -outputBlock ./channel-artifacts/plnchannel.block -channelID plnchannel

# # ---- Unir Orderer al Canal de Aplicación ----
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
peer lifecycle chaincode queryinstalled
./net-pln.sh invoke equipment GlobalEquipmentCorp 2000.001 e360-Ventilator GlobalEquipmentCorp
./net-pln.sh invoke query 2000.001
./net-pln.sh invoke wholesaler 2000.001 GlobalWholesalerCorp
sleep 2
./net-pln.sh invoke pharmacy 2000.001 PharmacyCorp
sleep 2
./net-pln.sh invoke queryHistory 2000.001

exit 0