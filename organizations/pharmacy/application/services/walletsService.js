/*
 # Hyperledger Smart Contract Development with Hyperledger Fabric V2
 # farma ledger supply chain network
 # Author: Juan Fuente
 # WalletService -addToWallet:
 # handle wholesaler org3 wallet
 */
'use strict';

// Bring key classes into scope, most importantly Fabric SDK network class
const fs = require('fs');
const { Wallets } = require('fabric-network');
const path = require('path');

// Usar variables de entorno
const WALLET_PATH_ENV = process.env.WALLET_PATH || '/wallet'; // Volumen mapeado
const ORG_NAME = process.env.ORG_NAME; // Ej: org3.example.com
const MSP_ID = process.env.ORG_MSP; // Ej: Org3MSP

class WalletService {
  async addToWallet(user) {
    try {
      if (!user || user.length < 1) {
        throw ({ status: 500, message: 'User is not defined.' });
      }
      //Validate environment variables
      if (!ORG_NAME || !MSP_ID || !WALLET_PATH_ENV) {
        console.error("Error: Missing required environment variables (CCP_PATH, WALLET_PATH).");
        throw ({ status: 500, message: 'Missing environment variables (ORG_NAME, MSP_ID, WALLET_PATH).' });
      }
      //Create a new file system based wallet for managing identities.
      const walletPath = path.resolve(WALLET_PATH_ENV);
      const wallet = await Wallets.newFileSystemWallet(walletPath);
      console.log(`Wallet path: ${walletPath}`);

      // Identity to credentials to be stored in the wallet
      const credPath = path.join('/config', 'users', `User1@${ORG_NAME}`); // Ajusta según tu estructura
      const certificate = fs.readFileSync(path.join(credPath, 'msp', 'signcerts', `User1@${ORG_NAME}-cert.pem`)).toString();
      const privateKey = fs.readFileSync(path.join(credPath, 'msp', 'keystore', 'priv_sk')).toString();
      // Load credentials into wallet
      const identityLabel = user;
      const identity = {
        credentials: { certificate, privateKey },
        mspId: MSP_ID,
        type: 'X.509'
      };
      const response = await wallet.put(identityLabel, identity);
      console.log(`addToWallet mspId:${MSP_ID} response: ${response}`);
      return response ? JSON.parse(response) : response;
    } catch (error) {
      console.log(`Error adding to wallet. ${error}`);
      throw ({ status: 500, message: `Error adding to wallet. ${error}` });
    }
  }
}
module.exports = WalletService;