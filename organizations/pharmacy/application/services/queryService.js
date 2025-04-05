/*
 # Hyperledger Smart Contract Development with Hyperledger Fabric V2
 # farma ledger supply chain network
 # Author: Juan Fuente
 # EquipmentService -makeEquipment:
 */
 'use strict';

 // Bring key classes into scope, most importantly Fabric SDK network class
 const fs = require('fs');
 const yaml = require('js-yaml');
 const { Wallets, Gateway } = require('fabric-network');
 const path = require('path'); // Necesario para construir rutas
 
 // LEER CONFIG DESDE VARIABLES DE ENTORNO (con valores por defecto opcionales)
 const CCP_PATH_ENV = process.env.CCP_PATH; // Ej: /config/connection-org1.json (DENTRO del contenedor)
 const WALLET_PATH_ENV = process.env.WALLET_PATH; // Ej: /wallet (DENTRO del contenedor)
 const CHANNEL_NAME_ENV = process.env.CHANNEL_NAME || 'plnchannel';
 const CHAINCODE_NAME_ENV = process.env.CHAINCODE_NAME || 'pharmaLedgerContract';
 const CONTRACT_NAME_SPACE_ENV = process.env.CONTRACT_NAME_SPACE || 'org.pln.PharmaLedgerContract'; // Si el namespace cambia
 
 class QueryService {
   /**
   * 1. Select an identity from a wallet
   * 2. Connect to org1 network gateway
   * 3. Access farma ledger supply chain network
   * 4. Construct request to queryByKey
   * 5. Submit invoke queryByKey transaction
   * 6. Process response
   * 7. Disconnect from the gateway
   * 8. Return result
   * 9. Handle errors
   * 10. Return result
   **/
   async queryByKey(userName, key) {
     //Validate environment variables
     if (!CCP_PATH_ENV || !WALLET_PATH_ENV) {
       console.error("Error: Missing required environment variables (CCP_PATH, WALLET_PATH).");
       throw ({ status: 500, message: "Server configuration error." });
     }
     //Create a new file system based wallet for managing identities.
     const walletPath = path.resolve(WALLET_PATH_ENV); // Usa la variable de entorno
     const wallet = await Wallets.newFileSystemWallet(walletPath);
     console.log(`Wallet path: ${walletPath}`);
 
     // A gateway defines the peers used to access Fabric networks
     const gateway = new Gateway();
     console.log('userName:' + userName + " key:" + key);
     if (!userName || userName.length < 1) {
       throw ({ status: 500, message: 'User Name is not defined.' });
     }
     if (!key || key.length < 1) {
       throw ({ status: 500, message: 'key is not defined.' });
     }
     try {
       // Load connection profile; will be used to locate a gateway
       const ccpPath = path.resolve(CCP_PATH_ENV); // Usa la variable de entorno
       console.log(`CCP path: ${ccpPath}`);
 
       let connectionOptions = {
         identity: userName,
         wallet: wallet,
         discovery: { enabled: true, asLocalhost: false }
       };
       // Connect to gateway using application specified parameters
       console.log(`Connecting to Fabric gateway as ${userName}...`);
       await gateway.connect(connectionProfile, connectionOptions);
       // Access farma ledger supply chain network
       console.log('Use network channel: plnchannel.');
       const network = await gateway.getNetwork('plnchannel');
       // Get addressability to farma ledger supply chain network contract
       console.log('Use org.pln.PharmaLedgerContract smart contract.');
       const contract = await network.getContract('pharmaLedgerContract', 'org.pln.PharmaLedgerContract');
       // query ledger data by key
       console.log('Submit pharmaledger querybyKey request.');
       const response = await contract.submitTransaction('queryByKey', key);
       //console.log(response);
       return response ? JSON.parse(response) : response;
     } catch (error) {
       console.log(`Error processing transaction. ${error}`);
       console.log(error.stack);
       throw ({ status: 500, message: `Error processing transaction. ${error}` });
     } finally {
       // Disconnect from the gateway
       console.log('Disconnect from Fabric gateway.')
       gateway.disconnect();
     }
   }
 }
 module.exports = QueryService;
 