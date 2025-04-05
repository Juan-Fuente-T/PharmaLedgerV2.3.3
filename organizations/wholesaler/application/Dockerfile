# Usar una imagen base de Node.js
FROM node:14-alpine

# Establecer el directorio de trabajo dentro del contenedor
WORKDIR /usr/src/app

# Copiar archivos de definición de dependencias
# ASUMIENDO que tienes un package.json y package-lock.json
COPY package*.json ./

# Instalar dependencias
RUN npm install

# Copiar el resto del código de la aplicación
COPY . .

ENV NODE_PATH=/usr/src/app/node_modules

# EXPOSE el puerto en el que app.js escucha (¡¡AJUSTA ESTE NÚMERO!!)
# Busca app.listen(...) en tu app.js. Supongamos que es 8080.
EXPOSE 30001

# Comando para ejecutar la aplicación cuando el contenedor arranque
CMD [ "node", "app.js" ]