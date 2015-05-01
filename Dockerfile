
# Gitolite server by Luispa, Nov 2014
#
# -----------------------------------------------------
#

# Desde donde parto...
#
FROM debian:jessie

# Autor de este Dockerfile
#
MAINTAINER Luis Palacios <luis@luispa.com>

# Pido que el frontend de Debian no sea interactivo
ENV DEBIAN_FRONTEND noninteractive

# ------- ------- ------- ------- ------- ------- -------
# Herramientas mínimas en todos mis contenedores
# ------- ------- ------- ------- ------- ------- -------
#
RUN apt-get update && \
    apt-get -y install 	locales \
    					net-tools \
                       	vim \
                       	supervisor \
                       	wget \
                       	curl \
                        rsyslog

# Preparo locales y Timezone
#
RUN locale-gen es_ES.UTF-8
RUN locale-gen en_US.UTF-8
RUN dpkg-reconfigure locales
RUN echo "Europe/Madrid" > /etc/timezone; dpkg-reconfigure -f noninteractive tzdata

# Workaround para el Timezone, en vez de montar el fichero en modo read-only:
# 1) En el DOCKERFILE
RUN mkdir -p /config/tz && mv /etc/timezone /config/tz/ && ln -s /config/tz/timezone /etc/
# 2) En el Script entrypoint:
#     if [ -d '/config/tz' ]; then
#         dpkg-reconfigure -f noninteractive tzdata
#         echo "Hora actual: `date`"
#     fi
# 3) Al arrancar el contenedor, montar el volumen, a contiuación un ejemplo:
#     /Apps/data/tz:/config/tz
# 4) Localizar la configuración:
#     echo "Europe/Madrid" > /Apps/data/tz/timezone
 
# HOME
ENV HOME /root

# ------- ------- ------- ------- ------- ------- -------
# Programas principales de este contenedor
# ------- ------- ------- ------- ------- ------- -------
#
RUN apt-get update && \
    apt-get -y install git \
                       openssh-server \
                       sudo
                             
# Importante para que sshd funcione... 
#
RUN mkdir /var/run/sshd

# Creo el usuario git en /home/git
# Notar que le asigno el mismo UID/GID 1600/1600 que tengo
# asignado al usuario git:git en el Host, de modo que el
# Volumen donde estan los repositorios aparece con el mismo uid/gid
RUN groupadd -g 1600 git
RUN useradd -u 1600 -g git -m -d /home/git -s /bin/bash git

# Descargo e instalo gitolite
#
RUN su - git -c 'git clone git://github.com/sitaramc/gitolite'
RUN su - git -c 'mkdir -p $HOME/bin \
              && gitolite/install -to $HOME/bin'

# Le pongo todos los permisos correctos al usuario
#
RUN chown -R git:git /home/git

# Para evitar error de login
# http://stackoverflow.com/questions/22547939/docker-gitlab-container-ssh-git-login-error
#
RUN sed -i '/session    required     pam_loginuid.so/d' /etc/pam.d/sshd

# ------- ------- ------- ------- ------- ------- -------
# DEBUG ( Descomentar durante debug del contenedor )
# ------- ------- ------- ------- ------- ------- -------
#
# Herramientas tcpdump y net-tools
#RUN apt-get update && \
#    apt-get -y install  tcpdump \
#                        net-tools
## Permitir que root pueda hacer login vía SSHD
#RUN echo 'root:docker' | chpasswd
#RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
#RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
#ENV NOTVISIBLE "in users profile"
#RUN echo "export VISIBLE=now" >> /etc/profile

## Script que uso a menudo durante sesiones interactivas, es un "cat" sin líneas de comentarios
#
RUN echo "grep -vh '^[[:space:]]*#' \"\$@\" | grep -v '^//' | grep -v '^;' | grep -v '^\$' | grep -v '^\!' | grep -v '^--'" > /usr/bin/confcat
RUN chmod 755 /usr/bin/confcat

#-----------------------------------------------------------------------------------

# Ejecutar siempre al arrancar el contenedor este script
#
ADD do.sh /do.sh
RUN chmod +x /do.sh
ENTRYPOINT ["/do.sh"]

#
# Si no se especifica nada se ejecutará lo siguiente: 
#
CMD ["/usr/bin/supervisord", "-n -c /etc/supervisor/supervisord.conf"]
