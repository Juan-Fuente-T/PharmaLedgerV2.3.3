# FROM node:14-alpine
FROM hyperledger/fabric-nodeenv:2.3
WORKDIR /usr/local/src
COPY package.json package-lock.json* ./
RUN npm install --production # Instala solo deps de producción

COPY . .
# Reconstruye módulos nativos para el Node del entorno de ejecución (Node 12.16.1)
RUN npm rebuild
# CMD ["node", "lib/pharmaledgercontract.js", "--peer.address", "peer0.org2.example.com:7052"] 
# CMD ["/bin/sh", "-c", "node chaincode.js 2>&1 | tee /tmp/chaincode.log && cat /tmp/chaincode.log && exit 0"]
# CMD ["node", "pharmaledgercontract.js"]