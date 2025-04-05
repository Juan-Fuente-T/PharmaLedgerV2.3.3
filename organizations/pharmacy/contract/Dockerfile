FROM node:14-alpine
WORKDIR /usr/local/src
COPY package*.json ./
RUN npm install
COPY . .
RUN ls -l /usr/local/src/lib 
# CMD ["node", "lib/pharmaledgercontract.js", "--peer.address", "peer0.org2.example.com:7052"] 
# CMD ["/bin/sh", "-c", "node chaincode.js 2>&1 | tee /tmp/chaincode.log && cat /tmp/chaincode.log && exit 0"]
CMD ["node", "pharmaledgercontract.js"]