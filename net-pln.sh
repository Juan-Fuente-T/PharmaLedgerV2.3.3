#!/bin/bash
#
# Juan Fuente Hyperledger Fabric V2
# farma ledger supply chain network
# network script to run end to end network setup, channel creation, smart contract deployment, invoke chain code and monitoring docker logs

# MODIFICADO: Asegurarse que estas variables no interfieran si son seteadas por el script que llama (reload.sh)
# export PATH=${PWD}/../bin:${PWD}:$PATH # Comentado: reload.sh ya debería setear el PATH
# export FABRIC_CFG_PATH=${PWD}/configtx # Comentado: reload.sh ya debería setear FABRIC_CFG_PATH
# Carga .env si existe
[ -f .env ] && source .env
export VERBOSE=false
export COMPOSE_PROJECT_NAME="net"
# Default image tag para peers y tools
IMAGETAG="${IMAGE_TAG:-2.3.3}"  # Usa IMAGE_TAG del .env o 2.5.12 como fallback
export IMAGE_TAG=$IMAGETAG  # Exportar para docker-compose
echo "INFO: Using image tag: ${IMAGE_TAG}"
# Default CA image tag (si usas CA, si no, déjalo comentado)
CA_IMAGETAG="${CA_IMAGE_TAG:-2.3.3}"  # Usa CA_IMAGE_TAG del .env o 2.5.12 como fallback
# export CA_IMAGE_TAG=$CA_IMAGETAG  # Descomenta si usas COMPOSE_FILE_CA
# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# Using cryptogen vs CA. default is cryptogen
CRYPTO="cryptogen"
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
MAX_RETRY=5
# default for delay between commands
CLI_DELAY=3
# channel name defaults to "plnchannel"
CHANNEL_NAME="plnchannel"
# use this as the default docker-compose yaml definition
COMPOSE_FILE_BASE=docker/docker-compose-pln-net.yaml
# certificate authorities compose file (si se usara)
# COMPOSE_FILE_CA=docker/docker-compose-ca.yaml
# CouchDB compose file (si se usara)
COMPOSE_FILE_COUCH=docker/docker-compose-couch.yaml
# use golang as the default language for chaincode
CC_SRC_LANGUAGE=javascript
# Chaincode version
VERSION=1
# default database
DATABASE="leveldb"

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  network.sh <Mode> [Flags]"
  echo "    <Mode>"
  echo "      - 'up' - bring up fabric orderer and peer nodes. No channel is created"
  echo "      - 'up createChannel' - DEPRECATED: Use 'up' and then handle channel creation externally." # MODIFICADO: Aclaración
  echo "      - 'createChannel' - DEPRECATED: Channel creation should be handled externally." # MODIFICADO: Aclaración
  echo "      - 'deploySmartContract' - deploy the pharmaledger chaincode on the channel"
  echo "      - 'down' - clear the network with docker-compose down"
  echo "      - 'restart' - restart the network"
  echo
  echo "    Flags:"
  echo "    -ca <use CAs> -  create Certificate Authorities to generate the crypto material"
  echo "    -c <channel name> - channel name to use (defaults to \"plnchannel\")"
  echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
  echo "    -r <max retry> - CLI times out after certain number of attempts (defaults to 5)"
  echo "    -d <delay> - delay duration in seconds (defaults to 3)"
  echo "    -l <language> - the programming language of the chaincode to deploy: go (default), java, javascript, typescript"
  echo "    -v <version>  - chaincode version. Must be a round number, 1, 2, 3, etc"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -cai <ca_imagetag> - the image tag to be used for CA (defaults to \"${CA_IMAGETAG}\")"
  echo "    -verbose - verbose mode"
  echo "  network.sh -h (print this message)"
  echo
  echo " Examples:"
  echo "  (Use reload.sh to manage full setup)" # MODIFICADO: Indicar uso preferido
  echo "  net-pln.sh up # Only starts containers"
  echo "  net-pln.sh down"
  echo "  net-pln.sh deploySmartContract # After channel is created externally"
}

# cleanup ontainer images
function clearContainers() {
  CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*/) {print $1}')
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

# Delete network images when you bring the network down
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "---- No images available for deletion ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Versions of fabric known not to work with the test network
BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

# make sure you have installed all required fabric binaries/images
function checkPrereqs() {
  ## Check if your have cloned the peer binaries and configuration files.
  peer version > /dev/null 2>&1

  # MODIFICADO: Ajuste en la comprobación del PATH, asumimos que viene de fuera
  if [[ $? -ne 0 ]]; then
     echo "ERROR! Peer binary not found in PATH."
     echo "Ensure Fabric binaries are in your PATH (e.g., set by reload.sh)."
    # echo
    # echo "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
    # echo "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
    exit 1
  fi
  # MODIFICADO: Eliminada la comprobación de ../config, no es relevante para solo levantar docker
  # if [[ $? -ne 0 || ! -d "../config" ]]; then
  #   echo "ERROR! Peer binary and configuration files not found.."
  #   echo
  #   echo "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
  #   echo "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
  #   exit 1
  # fi

  LOCAL_VERSION=$(peer version | sed -ne 's/ Version: //p')
  # MODIFICADO: Asegurarse que IMAGETAG está definido (puede venir de flags o default)
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:${IMAGETAG} peer version | sed -ne 's/ Version: //p' | head -1)


  echo "LOCAL_VERSION=$LOCAL_VERSION"
  echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    echo "=================== WARNING ==================="
    echo "  Local fabric binaries and docker images are  "
    echo "  out of  sync. This may cause problems.       "
    echo "==============================================="
  fi

  for UNSUPPORTED_VERSION in $BLACKLISTED_VERSIONS; do
    echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      echo "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match the versions supported by the test network."
      exit 1
    fi

    echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      echo "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match the versions supported by the test network."
      exit 1
    fi
  done
}


# MODIFICADO: Esta función YA NO DEBE SER LLAMADA por networkUp.
# La generación de crypto la hará reload.sh
function createOrgs() {

  # MODIFICADO: Añadido aviso si se llama por error.
  echo "WARNING: createOrgs function called, but artifact generation should be handled by the external script (reload.sh)."

  if [ -d "organizations/peerOrganizations" ]; then
    # MODIFICADO: No borrar si ya existen, reload.sh los habrá creado.
    # rm -Rf organizations/peerOrganizations && rm -Rf organizations/ordererOrganizations
    echo "INFO: organizations directories already exist. Skipping deletion."
  fi

  # Create crypto material using cryptogen
  if [ "$CRYPTO" == "cryptogen" ]; then
    which cryptogen
    if [ "$?" -ne 0 ]; then
      echo "cryptogen tool not found. exiting"
      exit 1
    fi
    echo
    echo "##########################################################"
    echo "##### Generate certificates using cryptogen tool (IF NEEDED) #####" # MODIFICADO
    echo "##########################################################"
    echo

    # MODIFICADO: Solo generar si NO existen, aunque idealmente NUNCA debería llegar aquí en el flujo normal con reload.sh
    if [ ! -d "organizations/peerOrganizations" ]; then
      echo "##########################################################"
      echo "############ Create Org1 Identities ######################"
      echo "##########################################################"

      set -x
      cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output="organizations"
      res=$?
      set +x
      if [ $res -ne 0 ]; then
        echo "Failed to generate certificates..."
        exit 1
      fi

      echo "##########################################################"
      echo "############ Create Org2 Identities ######################"
      echo "##########################################################"

      set -x
      cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output="organizations"
      res=$?
      set +x
      if [ $res -ne 0 ]; then
        echo "Failed to generate certificates..."
        exit 1
      fi
      echo "##########################################################"
      echo "############ Create Org3 Identities ######################"
      echo "##########################################################"

      set -x
      cryptogen generate --config=./organizations/cryptogen/crypto-config-org3.yaml --output="organizations"
      res=$?
      set +x
      if [ $res -ne 0 ]; then
        echo "Failed to generate certificates..."
        exit 1
      fi
      echo "##########################################################"
      echo "############ Create Orderer Org Identities ###############"
      echo "##########################################################"

      set -x
      cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output="organizations"
      res=$?
      set +x
      if [ $res -ne 0 ]; then
        echo "Failed to generate certificates..."
        exit 1
      fi
    else
        echo "INFO: organizations directory exists, skipping cryptogen generation."
    fi
  fi

  echo
  # MODIFICADO: La generación de CCP también debería hacerla reload.sh si es necesaria antes de 'up'.
  # echo "Generate CCP files for Org1, Org2 and Org3"
  # ./organizations/ccp-generate.sh
  echo "INFO: Skipping CCP generation within net-pln.sh. Assumed done by external script if needed."
}

# MODIFICADO: Esta función YA NO DEBE SER LLAMADA por networkUp.
# La generación del bloque génesis la hará reload.sh
function createConsortium() {

  # MODIFICADO: Añadido aviso si se llama por error.
  echo "WARNING: createConsortium function called, but genesis block generation should be handled by the external script (reload.sh)."

  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi

  echo "#########  Generating Orderer Genesis block (IF NEEDED) ##############" # MODIFICADO

  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!

#   # MODIFICADO: Solo generar si NO existe, aunque idealmente NUNCA debería llegar aquí en el flujo normal con reload.sh
#   if [ ! -f "./system-genesis-block/genesis.block" ]; then
#     set -x
#     # MODIFICADO: Asegurarse que FABRIC_CFG_PATH está seteado (debería venir de reload.sh)
#     configtxgen -profile PharmaLedgerOrdererGenesis -channelID system-channel -outputBlock ./system-genesis-block/genesis.block
#     res=$?
#     set +x
#     if [ $res -ne 0 ]; then
#       echo "Failed to generate orderer genesis block..."
#       exit 1
#     fi
#   else
#       echo "INFO: system-genesis-block/genesis.block exists, skipping generation."
#   fi
}

# Bring up the peer and orderer nodes using docker compose.
function networkUp() {

  checkPrereqs # Es bueno mantener la comprobación de prerequisitos

  # MODIFICADO: ELIMINADA la generación de artefactos desde aquí.
  # reload.sh debe haber generado los artefactos ANTES de llamar a net-pln.sh up.
  # # generate artifacts if they don't exist
  # if [ ! -d "organizations/peerOrganizations" ]; then
  #   createOrgs
  #   createConsortium
  # fi
  echo "INFO: Skipping artifact generation within networkUp. Assuming artifacts exist."

  COMPOSE_FILES="-f ${COMPOSE_FILE_BASE}"

  if [ "${DATABASE}" == "couchdb" ]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
  fi

  echo "INFO: Using image tag: ${IMAGE_TAG}"
  # Asegurarse que el tag se pasa a docker-compose
  export IMAGE_TAG=$IMAGETAG # Exportar la variable para que docker-compose la use

  # MODIFICADO: Llamada directa a docker-compose up
  echo "INFO: Starting Fabric network containers using compose files: ${COMPOSE_FILES}"
  # docker-compose ${COMPOSE_FILES} up -d 2>&1 # Redirección original comentada
  docker compose ${COMPOSE_FILES} up -d
  # IMAGE_TAG=2.2.12 # Comentado, debe usar la variable

  docker ps -a
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network containers"
    exit 1
  fi
  echo "INFO: Fabric network containers started."
}

## MODIFICADO: Esta función YA NO DEBE SER LLAMADA por el flujo principal.
## La creación/join de canal la hará reload.sh
function createChannel() {

  # MODIFICADO: Añadido aviso de obsolescencia.
  echo "WARNING: createChannel function called, but channel creation/joining should be handled by the external script (reload.sh)."
  echo "WARNING: This function will now exit to prevent unintended actions."
  exit 1 # Salir para evitar que ejecute el script createChannel.sh

  # MODIFICADO: El código original que sigue está ahora inactivo debido al exit 1 anterior.
  if [ ! -d "organizations/peerOrganizations" ]; then
    echo "Bringing up network"
    networkUp
  fi
  scripts/createChannel.sh $CHANNEL_NAME $CLI_DELAY $MAX_RETRY $VERBOSE
  if [ $? -ne 0 ]; then
    echo "Error !!! Create channel failed"
    exit 1
  fi
}

## deploy smart contract - SIN CAMBIOS, puede ser útil llamarlo después
function deploySmartContract() {
  # MODIFICADO: Añadir comprobación de que la red está levantada
  if ! docker ps -a --format '{{.Names}}' | grep -q "peer0.org1.example.com"; then
      echo "ERROR: Network does not seem to be running. Cannot deploy smart contract."
      exit 1
  fi
  echo "INFO: Attempting to deploy smart contract..."
  scripts/deploySmartContract.sh $CHANNEL_NAME $CC_SRC_LANGUAGE $VERSION $CLI_DELAY $MAX_RETRY $VERBOSE
  if [ $? -ne 0 ]; then
    echo "ERROR !!! Deploying chaincode failed"
    exit 1
  fi

  exit 0
}
# invoke contract - SIN CAMBIOS
function invokeContract() {
  # MODIFICADO: Añadir comprobación de que la red está levantada
  if ! docker ps -a --format '{{.Names}}' | grep -q "peer0.org1.example.com"; then
      echo "ERROR: Network does not seem to be running. Cannot invoke contract."
      exit 1
  fi
  echo "INFO: Attempting to invoke contract..."
  scripts/invokeContract.sh "$@"
  if [ $? -ne 0 ]; then
    echo "ERROR !!! Invoking contract failed"
    exit 1
  fi

  exit 0
}
# monitor up - SIN CAMBIOS
function  monitorUp() {
  scripts/monitor.sh
}
# monitor down - SIN CAMBIOS
function  monitorDown() {
   docker kill logspout || true
}
# Tear down running network - SIN CAMBIOS EN LA LÓGICA PRINCIPAL
function networkDown() {
  echo "INFO: Tearing down Fabric network..."
  # stop all orgs containers
  # MODIFICADO: Asegurar que usa el compose file correcto
  COMPOSE_FILES="-f ${COMPOSE_FILE_BASE}"
  if [ "${DATABASE}" == "couchdb" ]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
  fi
  docker compose ${COMPOSE_FILES} down --volumes --remove-orphans

  # Don't remove the generated artifacts -- note, the ledgers are always removed
  if [ "$MODE" != "restart" ]; then
    echo "INFO: Cleaning up containers and images..."
    # Bring down the network, deleting the volumes
    #Cleanup the chaincode containers
    clearContainers
    #Cleanup images
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    echo "INFO: Removing generated artifacts..."
    # MODIFICADO: Usar sudo si es necesario (basado en tu script reload.sh)
    sudo rm -rf system-genesis-block # Limpiar bloque génesis
    sudo rm -rf channel-artifacts # Limpiar artefactos de canal
    sudo rm -rf organizations/peerOrganizations organizations/ordererOrganizations # Limpiar crypto
    ## remove fabric ca artifacts (si se usaran CAs)
    # sudo rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db
    # sudo rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db
    # sudo rm -rf organizations/fabric-ca/org3/msp organizations/fabric-ca/org3/tls-cert.pem organizations/fabric-ca/org3/ca-cert.pem organizations/fabric-ca/org3/IssuerPublicKey organizations/fabric-ca/org3/IssuerRevocationPublicKey organizations/fabric-ca/org3/fabric-ca-server.db
    # sudo rm -rf organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db

    # remove channel and script artifacts
    sudo rm -rf log.txt pharmaledgernetwork.tar.gz # Limpiar otros posibles artefactos
    # MODIFICADO: Limpiar la wallet de explorer también si existe
    sudo rm -rf wallet
    echo "INFO: Artifact cleanup complete."
  fi
  echo "INFO: Network teardown complete."
}

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]] ; then
  printHelp
  exit 0
else
  MODE=$1
  shift
fi

# parse a createChannel subcommand if used
# MODIFICADO: Deshabilitar el subcomando 'createChannel' ya que ahora es manejado externamente
if [[ $# -ge 1 ]] ; then
  key="$1"
  if [[ "$key" == "createChannel" ]]; then
      # export MODE="createChannel" # No cambiar el modo
      echo "INFO: 'up createChannel' is deprecated. Using 'up' mode only."
      echo "INFO: Channel creation should be handled by the calling script (e.g., reload.sh)."
      shift
  fi
fi

# parse flags
if [ "${MODE}" != "invoke" ]; then
  while [[ $# -ge 1 ]] ; do
    key="$1"
    case $key in
    -h )
      printHelp
      exit 0
      ;;
    -c )
      CHANNEL_NAME="$2"
      shift
      ;;
    -r )
      MAX_RETRY="$2"
      shift
      ;;
    -d )
      CLI_DELAY="$2"
      shift
      ;;
    -s )
      DATABASE="$2"
      shift
      ;;
    -l )
      CC_SRC_LANGUAGE="$2"
      shift
      ;;
    -v )
      VERSION="$2"
      shift
      ;;
    -i )
      IMAGETAG="$2"
      shift
      ;;
    -cai )
      CA_IMAGETAG="$2"
      shift
      ;;
    -verbose )
      VERBOSE=true
      # MODIFICADO: Pasar verbose a scripts llamados si es necesario
      export VERBOSE # Exportar para que scripts hijos lo vean
      shift
      ;;
    * )
      echo
      echo "Unknown flag: $key"
      echo
      printHelp
      exit 1
      ;;
    esac
    shift
  done
fi
# Are we generating crypto material with this command?
# MODIFICADO: Esta lógica ya no es relevante aquí, reload.sh genera el crypto.
# if [ ! -d "organizations/peerOrganizations" ]; then
#   CRYPTO_MODE="with crypto from '${CRYPTO}'"
# else
#   CRYPTO_MODE=""
# fi
CRYPTO_MODE="(Assuming crypto generated externally by ${CRYPTO})" # Mensaje informativo

# Determine mode of operation and printing out what we asked for
if [ "$MODE" == "up" ]; then
  echo "Starting Fabric nodes ONLY." # MODIFICADO: Aclaración
  echo "Using CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE}' ${CRYPTO_MODE}"
  echo
elif [ "$MODE" == "createChannel" ]; then
  # MODIFICADO: Ya no se debería llegar aquí por el cambio en el parseo de 'up createChannel'
  # y el 'exit 1' en la función createChannel. Pero por si acaso:
  echo "DEPRECATED: Creating channel '${CHANNEL_NAME}'."
  echo "Channel creation should be handled by an external script (e.g., reload.sh)."
  echo
elif [ "$MODE" == "down" ]; then
  echo "Stopping network and cleaning up artifacts..." # MODIFICADO: Aclaración
  echo
elif [ "$MODE" == "restart" ]; then
  echo "Restarting network (down + up containers only)..." # MODIFICADO: Aclaración
  echo
elif [ "$MODE" == "deploySmartContract" ]; then
  echo "Deploying chaincode on channel '${CHANNEL_NAME}'"
  echo
elif [ "$MODE" == "invoke" ]; then
  echo "Invoking chaincode function on channel '${CHANNEL_NAME}'"
  echo
elif [ "$MODE" == "monitor-up" ]; then
  echo "Starting docker log monitoring on network '${COMPOSE_PROJECT_NAME}_pln'"
  echo
elif [ "$MODE" == "monitor-down" ]; then
  echo "Stopping docker log monitoring on network '${COMPOSE_PROJECT_NAME}_pln'"
  echo
else
  printHelp
  exit 1
fi

# --- Ejecución Principal ---
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "createChannel" ]; then
  # createChannel # MODIFICADO: Comentado/Deshabilitado explícitamente.
  echo "ERROR: 'createChannel' mode is disabled. Please use reload.sh or similar."
  exit 1
elif [ "${MODE}" == "deploySmartContract" ]; then
  deploySmartContract
elif [ "${MODE}" == "invoke" ]; then
  invokeContract "$@"
elif [ "${MODE}" == "monitor-up" ]; then
  monitorUp
elif [ "${MODE}" == "monitor-down" ]; then
  monitorDown
elif [ "${MODE}" == "down" ]; then
  networkDown
elif [ "${MODE}" == "restart" ]; then
  networkDown
  networkUp # Llama a la versión modificada de networkUp que solo levanta contenedores
else
  printHelp
  exit 1
fi

exit 0 # Salida limpia si todo fue bien