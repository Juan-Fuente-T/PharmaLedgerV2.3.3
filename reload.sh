# Script para reiniciar la red de Hyperledger Fabric y realizar tareas de limpieza y configuración.

# Instalar NVM y Node.js
# nvm install 16.20.2
# nvm use 16.20.2
# nvm alias default 16

# Instalar jq
# sudo apt-get install jq -y

# ---- Configuración ----
export FABRIC_CFG_PATH=${PWD}/configtx
# Asegúrate que el binario 'peer' está en el PATH
export PATH=${PWD}/../bin:${PWD}:$PATH # Ajusta ../bin si es necesario

# Variables reutilizables
export CHANNEL_NAME="plnchannel"
export ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt # O la del Admin si es distinta
export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key # O la del Admin si es distinta

# Variables específicas de Org1
export ORG1_MSP="Org1MSP"
export ORG1_PEER0_HOST="peer0.org1.example.com"
export ORG1_PEER0_PORT="7051"
export ORG1_PEER0_ADDR="${ORG1_PEER0_HOST}:${ORG1_PEER0_PORT}"
export ORG1_ADMIN_MSP_PATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export ORG1_PEER0_TLS_ROOTCERT=${PWD}/organizations/peerOrganizations/org1.example.com/peers/${ORG1_PEER0_HOST}/tls/ca.crt

# (Añade variables similares para Org2 y Org3 si necesitas unirlas aquí también)
export ORG2_MSP="Org2MSP"
export ORG2_PEER0_HOST="peer0.org2.example.com"
export ORG2_PEER0_PORT="9051" # Verifica este puerto en tu docker-compose
export ORG2_PEER0_ADDR="${ORG2_PEER0_HOST}:${ORG2_PEER0_PORT}"
export ORG2_ADMIN_MSP_PATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export ORG2_PEER0_TLS_ROOTCERT=${PWD}/organizations/peerOrganizations/org2.example.com/peers/${ORG2_PEER0_HOST}/tls/ca.crt

export ORG3_MSP="Org3MSP"
export ORG3_PEER0_HOST="peer0.org3.example.com"
export ORG3_PEER0_PORT="11051" # Verifica este puerto en tu docker-compose
export ORG3_PEER0_ADDR="${ORG3_PEER0_HOST}:${ORG3_PEER0_PORT}"
export ORG3_ADMIN_MSP_PATH=${PWD}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
export ORG3_PEER0_TLS_ROOTCERT=${PWD}/organizations/peerOrganizations/org3.example.com/peers/${ORG3_PEER0_HOST}/tls/ca.crt

# ---- Limpieza Profunda ----
echo "****** Limpiando entorno anterior... ******"
sudo -v
./net-pln.sh down || echo "Fallo al bajar la red (puede que no estuviera arriba)."
docker stop $(docker ps -a -q) 2>/dev/null || echo "No hay contenedores que parar."
docker rm $(docker ps -a -q) 2>/dev/null || echo "No hay contenedores que borrar."
docker network prune -f
docker volume prune -f # Importante limpiar volúmenes
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

echo "****** Asegurando permisos correctos para directorios... ******"
# Aplica chown a los directorios específicos donde se escribirán cosas.
sudo chown -R juan:juan ./organizations ./wallet ./system-genesis-block ./channel-artifacts
# Opcional: Asegurar permisos de ejecución si hubiera scripts dentro, etc.
# sudo chmod -R u+rwx ./organizations ./wallet ./system-genesis-block ./channel-artifacts


echo "****** Generando artefactos criptográficos ******"
cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-org3.yaml --output=organizations
cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output=organizations

# Si cryptogen se ejecutó como root, arregla permisos
# sudo chown -R juan:juan ./organizations
# sudo chmod -R u+rwx ./organizations

echo "****** Asegurando permisos de ejecución para ccp-generate.sh ******"
chmod +x ./organizations/ccp-generate.sh 

echo "****** Ahora sí, generando CCPs ******"
./organizations/ccp-generate.sh 

echo "****** Verificando tipo DESPUÉS de ccp-generate... ******"

ls -la ./organizations/peerOrganizations/org1.example.com/ # Muestra resultado final/organizations/peerOrganizations/org1.example.com/ # Muestra resultado final

# ---- (Opcional) Preparar Wallet Explorer ----
echo "****** Configurando Hyperledger Explorer wallet... ******"
ADMIN_KEY_FILE=$(find ./organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/ -name '*_sk' -type f -print -quit)
if [ -z "$ADMIN_KEY_FILE" ]; then
  echo "ERROR: No se encontró el archivo de clave privada para Admin@org1.example.com"
  exit 1
fi
echo "Archivo de clave privada encontrado: $ADMIN_KEY_FILE"
mkdir -p ./wallet/admin
cp "$ADMIN_KEY_FILE" ./wallet/admin/private_key
cp ./organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/Admin@org1.example.com-cert.pem ./wallet/admin/certificate

# ---- Generar Bloque Génesis y Transacción de Canal ----
echo "****** Generando bloque génesis... ******"
# configtxgen -profile PharmaLedgerOrdererGenesis -channelID system-channel -outputBlock ./system-genesis-block/genesis.block

echo "****** Generando transacción de creación de canal... ******"
# configtxgen -profile PharmaLedgerChannel -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME}.tx -channelID ${CHANNEL_NAME}
configtxgen -profile PharmaLedgerChannel -outputBlock ./channel-artifacts/plnchannel.block -channelID plnchannel

# ---- Levantar la Red (Solo contenedores) ----
echo "****** Levantando la red Fabric (contenedores)... ******"
# ASEGÚRATE QUE net-pln.sh NO crea ni une canales ahora
ls -l ./channel-artifacts/plnchannel.block
./net-pln.sh up
echo "Esperando a que los contenedores se estabilicen (30s)..."
sleep 30 # Ajusta si es necesario

echo "****** Haciendo que Orderer se una al canal ${CHANNEL_NAME}... ******"
# Necesitamos exportar variables para osnadmin
export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt # Cert del Admin del Orderer (o el que uses para admin)
export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key # Clave del Admin del Orderer
export ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt # CA Raíz TLS del Orderer (para verificar su cert)

# El comando osnadmin channel join
osnadmin channel join --channelID ${CHANNEL_NAME} --config-block ./channel-artifacts/${CHANNEL_NAME}.block -o localhost:7053 --ca-file "${ORDERER_CA}" --client-cert "${ORDERER_ADMIN_TLS_SIGN_CERT}" --client-key "${ORDERER_ADMIN_TLS_PRIVATE_KEY}"

echo "****** Orderer unido al canal ${CHANNEL_NAME} (o intento realizado) ******"
sleep 5 # Darle tiempo al orderer

# ---- Crear Canal (Ejecutado desde aquí) ----
echo "****** Creando canal ${CHANNEL_NAME}... ******"
# Establecer contexto para el Admin de Org1 para crear canal
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=$ORG1_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG1_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:${ORG1_PEER0_PORT} # Necesitamos un peer para enviar, aunque va al orderer
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_PEER0_TLS_ROOTCERT # TLS del peer al que nos conectamos

# peer channel create -o localhost:7050 -c ${CHANNEL_NAME} -f ./channel-artifacts/${CHANNEL_NAME}.tx --outputBlock ./channel-artifacts/${CHANNEL_NAME}.block --tls --cafile ${ORDERER_CA}
# echo "****** Canal ${CHANNEL_NAME} creado ******"
# sleep 5 # Pausa corta

# ---- Unir Peer Org1 al Canal (Ejecutado desde aquí) ----
echo "****** Uniendo peer0.org1 al canal ${CHANNEL_NAME}... ******"
# Contexto sigue siendo Admin de Org1, dirección apunta al peer de Org1
export CORE_PEER_ADDRESS=localhost:${ORG1_PEER0_PORT} # Asegura que apunta al peer correcto
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_PEER0_TLS_ROOTCERT # TLS del peer al que nos conectamos
# CORE_PEER_LOCALMSPID y CORE_PEER_MSPCONFIGPATH ya están seteados para Admin Org1

peer channel join -b ./channel-artifacts/plnchannel.block
echo "****** Peer ${ORG1_PEER0_HOST} unido al canal ${CHANNEL_NAME} ******"
sleep 3

# ---- Unir Peer Org2 al Canal ----
echo "****** Uniendo peer0.org2 al canal ${CHANNEL_NAME}... ******"
# Cambiar contexto al Admin de Org2
export CORE_PEER_LOCALMSPID=$ORG2_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:${ORG2_PEER0_PORT} # Apunta a peer0.org2
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_PEER0_TLS_ROOTCERT # TLS de peer0.org2

peer channel join -b ./channel-artifacts/${CHANNEL_NAME}.block
echo "****** Peer ${ORG2_PEER0_HOST} unido al canal ${CHANNEL_NAME} ******"
sleep 3

# ---- Unir Peer Org3 al Canal ----
echo "****** Uniendo peer0.org3 al canal ${CHANNEL_NAME}... ******"
# Cambiar contexto al Admin de Org3
export CORE_PEER_LOCALMSPID=$ORG3_MSP
export CORE_PEER_MSPCONFIGPATH=$ORG3_ADMIN_MSP_PATH
export CORE_PEER_ADDRESS=localhost:${ORG3_PEER0_PORT} # Apunta a peer0.org3
export CORE_PEER_TLS_ROOTCERT_FILE=$ORG3_PEER0_TLS_ROOTCERT # TLS de peer0.org3

peer channel join -b ./channel-artifacts/${CHANNEL_NAME}.block
echo "****** Peer ${ORG3_PEER0_HOST} unido al canal ${CHANNEL_NAME} ******"

# cd pharma-ledger-network/organizations/manufacturer/contract
# npm install

export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=$PWD/config/

# ######  PEER0.ORG1.EXAMPLE.COM  ######
export CORE_PEER_TLS_ENABLED=true
# Ruta al certificado TLS para peer0.org1.example.com
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
# MSP de la organización para peer0.org1.example.com
# export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_LOCALMSPID=Org1MSP
# Ruta al certificado raíz TLS
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG1_CA
# Ruta al directorio MSP de Admin de org1 (usuarios Admin)
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
# Dirección del peer (puerto de peer0.org1.example.com)
export CORE_PEER_ADDRESS=localhost:7051
echo -e "\e[1;32m"
echo -e "┌──────────────────────────────────────────────────────────────────────────────┐"
echo -e "│PEER0.ORG1.EXAMPLE.COM : peer channel list                                    │"
echo -e "└──────────────────────────────────────────────────────────────────────────────┘\e[0m"
echo -e ""
peer channel list
# ######  PEER0.ORG2.EXAMPLE.COM  ######
export CORE_PEER_TLS_ENABLED=true
# Ruta al certificado TLS para peer0.org2.example.com
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
# MSP de la organización para peer0.org2.example.com
# export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_LOCALMSPID=Org2MSP
# Ruta al certificado raíz TLS
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG2_CA
# Ruta al directorio MSP de Admin de org2 (usuarios Admin)
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
# Dirección del peer (puerto de peer0.org1.example.com)
export CORE_PEER_ADDRESS=localhost:9051
echo -e "\e[1;32m"
echo -e "┌──────────────────────────────────────────────────────────────────────────────┐"
echo -e "│PEER0.ORG2.EXAMPLE.COM : peer channel list                                    │"
echo -e "└──────────────────────────────────────────────────────────────────────────────┘\e[0m"
echo -e ""
peer channel list
# ######  PEER0.ORG3.EXAMPLE.COM  ######
export CORE_PEER_TLS_ENABLED=true
# Ruta al certificado TLS para peer0.org3.example.com
export PEER0_ORG3_CA=${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt
# MSP de la organización para peer0.org3.example.com
# export CORE_PEER_LOCALMSPID="Org3MSP"
export CORE_PEER_LOCALMSPID=Org3MSP
# Ruta al certificado raíz TLS
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG3_CA
# Ruta al directorio MSP de Admin de org3 (usuarios Admin)
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
# Dirección del peer (puerto de peer0.org3.example.com)
export CORE_PEER_ADDRESS=localhost:11051
echo -e "\e[1;32m"
echo -e "┌──────────────────────────────────────────────────────────────────────────────┐"
echo -e "│PEER0.ORG3.EXAMPLE.COM : peer channel list                                    │"
echo -e "└──────────────────────────────────────────────────────────────────────────────┘\e[0m"
echo -e ""
peer channel list

# ReinicIA Hyperledger Explorer
docker restart hyperledger-explorer

./net-pln.sh deploySmartContract

peer lifecycle chaincode queryinstalled

# ./net-pln.sh invoke equipment GlobalEquipmentCorp 2000.001 e360-Ventilator GlobalEquipmentCorp
# ./net-pln.sh invoke query 2000.001
# ./net-pln.sh invoke wholesaler 2000.001 GlobalWholesalerCorp
# ./net-pln.sh invoke pharmacy 2000.001 PharmacyCorp
# ./net-pln.sh invoke queryHistory 2000.001

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
exit 0