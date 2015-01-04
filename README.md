# Introducción

Este repositorio alberga un *contenedor Docker* para montar un Servidor GIT privado usando "gitolite", está automatizado en el Registry Hub de Docker [luispa/base-gitolite](https://registry.hub.docker.com/u/luispa/base-gitolite/) conectado con el el proyecto en [GitHub base-gitolite](https://github.com/LuisPalacios/base-gitolite)

Consulta este [apunte técnico sobre varios servicios en contenedores Docker](http://www.luispa.com/?p=172) para acceder a otros contenedores Docker y sus fuentes en GitHub.


## Ficheros

* **Dockerfile**: Para crear servidor GIT basado en debian y gitolite
* **do.sh**: Se utiliza para arrancar correctamente el contenedor creado con esta imagen

## Instalación de la imagen

Para usar la imagen desde el registry de docker hub

    ~ $ docker pull luispa/base-gitolite


## Clonar el repositorio

Este es el comando a ejecutar para clonar el repositorio desde GitHub y poder trabajar con él directametne

    ~ $ clone https://github.com/LuisPalacios/docker-gitolite.git

Luego puedes crear la imagen localmente con el siguiente comando

    $ docker build -t luispa/base-gitolite ./
