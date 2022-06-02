FROM node:16.1-alpine3.11
LABEL author="Piyush Gupta"
ENV  NODE_ENV=production
ENV PORT=3000

#Directory of Docker Container
WORKDIR /var/morphir_home

COPY ./tests-integration/reference-model ./
RUN npm install -g morphir-elm && morphir-elm make

EXPOSE $PORT
ENTRYPOINT ["morphir-elm","develop"]
#docker run --name ContainerName -p 3000:3000 ImageID