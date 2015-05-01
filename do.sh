#!/bin/bash
#
# Punto de entrada para el servicio GIT
#
# Activar el debug de este script:
# set -eux

##################################################################
#
# main
#
##################################################################

# Averiguar si se ha configurado ya gitolite
#
INSTALACION_GITOLITE_NUEVA="no"
# Cambio al directorio del usuario GIT
cd /home/git
if [ ! -d ./.gitolite ] ; then
    INSTALACION_GITOLITE_NUEVA="si"
fi

# Averiguar si necesito configurar por primera vez
#
CONFIG_DONE="/.config_gitolite_done"
NECESITA_PRIMER_CONFIG="si"
if [ -f ${CONFIG_DONE} ] ; then
    NECESITA_PRIMER_CONFIG="no"
fi


##################################################################
#
# PREPARAR timezone
#
##################################################################
# Workaround para el Timezone, en vez de montar el fichero en modo read-only:
# 1) En el DOCKERFILE
#    RUN mkdir -p /config/tz && mv /etc/timezone /config/tz/ && ln -s /config/tz/timezone /etc/
# 2) En el Script entrypoint:
if [ -d '/config/tz' ]; then
    dpkg-reconfigure -f noninteractive tzdata
    echo "Hora actual: `date`"
fi
# 3) Al arrancar el contenedor, montar el volumen, a contiuación un ejemplo:
#     /Apps/data/tz:/config/tz
# 4) Localizar la configuración:
#     echo "Europe/Madrid" > /Apps/data/tz/timezone

##################################################################
#
# VARIABLES OBLIGATORIAS
#
##################################################################

## Servidor:Puerto por el que escucha el agregador de Logs (fluentd)
#
if [ -z "${FLUENTD_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto por el que escucha fluentd, variable: FLUENTD_LINK"
	exit 1
fi
fluentdHost=${FLUENTD_LINK%%:*}
fluentdPort=${FLUENTD_LINK##*:}

##################################################################
#
# CONFIGURACIÓN PREVIA DEL CONTENEDOR
#
##################################################################

# Asegurarme de que mi directorio .ssh tiene los permisos apropiados
#
if [ -d ./.ssh ]; then
    chown -R git:git ./.ssh
fi


# Me aseguro de mostrar cual es la clave publica del usuario git dentro del contenedor
# Si no la tiene la creo, va a necesitarse en entornos donde se usa mirroring.
#
if [ ! -f ./.ssh/id_rsa ]; then
   su git -c "ssh-keygen -f /home/git/.ssh/id_rsa  -t rsa -N ''"
fi
echo "Clave pública del usuario git:"
echo "_______________________________________________________________________________"
cat /home/git/.ssh/id_rsa.pub
echo "_______________________________________________________________________________"


# Soporte de hosts de confianza (para setups con mirroring)
#
if [ ! -f ./.ssh/known_hosts ]; then
    if [ -n "${HOST_CONFIANZA}" ]; then
        echo "Genero un fichero known_hosts con el contenido de la variable \${HOST_CONFIANZA}"
        su git -c "ssh-keyscan -H ${HOST_CONFIANZA} > /home/git/.ssh/known_hosts"
    fi
fi

#
# Si en el repositorio existe un fichero .gitolite.rc lo copio
#
if [ -f ./repositories/.gitolite.rc ]; then
    cp ./repositories/.gitolite.rc ./
    chown git:git .gitolite.rc
fi


##################################################################
#
# PREPARAR EL CONTAINER PARA GITOLITE
#
##################################################################


# Necesito configurar por primera vez?
#
if [ ${INSTALACION_GITOLITE_NUEVA} = "si" ] ; then
    #
    # Tengo el directorio de repositorios?
    if [ -d ./repositories ] ; then

        # Ya existe ./repositories, tiene pinta que lo montaron con -v
        # y es muy probable que se trata de repositorios existentes
        chown -R git:git repositories

        #
        # Lo importante ¿REUTILIZO o CREO REPOSITORIO NUEVO?
        #
        if [ -d ./repositories/gitolite-admin.git ]; then

            # Si existe gitolite-admin.git es que estamos ante una reutilización de
            # un repositorio externo ya existente, así que actúo en consecuencia
            #
            echo "-- Instalación nueva pero con REPORSITORIO EXISTENTE, me integro con él"
            mv ./repositories/gitolite-admin.git ./repositories/gitolite-admin.git-tmp
            su git -c "bin/gitolite setup -a dummy"
            rm -rf ./repositories/gitolite-admin.git
            mv ./repositories/gitolite-admin.git-tmp ./repositories/gitolite-admin.git

            # Personalizo el fichero .gitolite.rc
            rcfile=/home/git/.gitolite.rc
            sed -i "s/GIT_CONFIG_KEYS.*=>.*''/GIT_CONFIG_KEYS => \"${GIT_CONFIG_KEYS}\"/g" $rcfile
            if [ -n "$LOCAL_CODE" ]; then
                sed -i "s|# LOCAL_CODE.*=>.*$|LOCAL_CODE => \"${LOCAL_CODE}\",|" $rcfile
            fi
 
            # Importo gitolite.conf y keydir/* desde gitolite-admin.git
            su git -c "mkdir ~/tmp                                                     && \
                       cd ~/tmp                                                        && \
                       git clone /home/git/repositories/gitolite-admin.git             && \
                       cp -R ~/tmp/gitolite-admin/conf/gitolite.conf ~/.gitolite/conf  && \
                       cp -R ~/tmp/gitolite-admin/keydir ~/.gitolite                   && \
                       rm -fr ~/tmp"
            su git -c "GL_LIBDIR=$(/home/git/bin/gitolite query-rc GL_LIBDIR) PATH=$PATH:/home/git/bin gitolite compile"
            
            # Arreglo los links que puedan estar mal en el repositorio existente
            su git -c "GL_LIBDIR=$(/home/git/bin/gitolite query-rc GL_LIBDIR) PATH=$PATH:/home/git/bin gitolite setup"
            
        else

		    # El repositorio gitolite-admin.git no existe, así que creo uno desde cero
            # Es importante tener la clave SSH_KEY o no podremos hacerlo
            
            # Creo un repositorio nuevo
            if [ -n "$SSH_KEY" ]; then
                # Importo la clave desde SSH_KEY y hago el gitolite setup
                echo "$SSH_KEY" > /tmp/admin.pub
                su git -c "bin/gitolite setup -pk /tmp/admin.pub"
                rm /tmp/admin.pub
            else
                # Error !!!
                echo " ======= ERROR !!! No puedo crear un REPO nuevo porque no me han pasado la variable SSH_KEY !!!!"
                echo "         Ejecutar con: -e SSH_KEY=\"\$(cat \$FICHERO_CLAVE_SSH)\""
                exit 255
            fi    
        fi        
    fi

else
    # Instalación existente, simplemente ejecuto 'gitolite setup' para resincronizar
	echo "-- Instalación existente de gitolite, sincronizo con ella..."        
    su git -c "bin/gitolite setup"	
fi

##################################################################
#
# PREPARAR EL CONTAINER POR PRIMERA VEZ
#
##################################################################

# Necesito configurar por primera vez?
#
if [ ${NECESITA_PRIMER_CONFIG} = "si" ] ; then
	
	############
	#
	# Configurar rsyslogd para que envíe logs a un agregador remoto
	#
	############
	echo "Configuro rsyslog.conf"

    cat > /etc/rsyslog.conf <<EOFRSYSLOG
\$LocalHostName gitolite
\$ModLoad imuxsock # provides support for local system logging
#\$ModLoad imklog   # provides kernel logging support
#\$ModLoad immark  # provides --MARK-- message capability

# provides UDP syslog reception
#\$ModLoad imudp
#\$UDPServerRun 514

# provides TCP syslog reception
#\$ModLoad imtcp
#\$InputTCPServerRun 514

# Activar para debug interactivo
#
#\$DebugFile /var/log/rsyslogdebug.log
#\$DebugLevel 2

\$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat

\$FileOwner root
\$FileGroup adm
\$FileCreateMode 0640
\$DirCreateMode 0755
\$Umask 0022

#\$WorkDirectory /var/spool/rsyslog
#\$IncludeConfig /etc/rsyslog.d/*.conf

# Dirección del Host:Puerto agregador de Log's con Fluentd
#
*.* @@${fluentdHost}:${fluentdPort}

# Activar para debug interactivo
#
# *.* /var/log/syslog

EOFRSYSLOG

	############
	#
	# Supervisor
	# 
	############
	echo "Configuro supervisord.conf"

	cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock 					; path to your socket file

[inet_http_server]
port = 0.0.0.0:9001								; allow to connect from web browser to supervisord

[supervisord]
logfile=/var/log/supervisor/supervisord.log 	; supervisord log file
logfile_maxbytes=50MB 							; maximum size of logfile before rotation
logfile_backups=10 								; number of backed up logfiles
loglevel=error 									; info, debug, warn, trace
pidfile=/var/run/supervisord.pid 				; pidfile location
minfds=1024 									; number of startup file descriptors
minprocs=200 									; number of process descriptors
user=root 										; default user
childlogdir=/var/log/supervisor/ 				; where child log files will live

nodaemon=false 									; run supervisord as a daemon when debugging
;nodaemon=true 									; run supervisord interactively (production)
 
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
 
[supervisorctl]
serverurl=unix:///var/run/supervisor.sock		; use a unix:// URL for a unix socket 

# Para enviar logs
[program:rsyslog]
process_name = rsyslogd
command=/usr/sbin/rsyslogd -n
startsecs = 0
autorestart = true

# Ejecución principal de este contenedor, GIT se accede vía SSHD
[program:sshd]
process_name = sshd
command=/usr/sbin/sshd -D
startsecs = 0
autorestart = true

EOF

    #
    # Creo el fichero de control para que el resto de 
    # ejecuciones no realice la primera configuración
    > ${CONFIG_DONE}
	
fi

##################################################################
#
# EJECUCIÓN DEL COMANDO SOLICITADO
#
##################################################################
#
exec "$@"
