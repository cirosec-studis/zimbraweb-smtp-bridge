FROM alpine:latest

# Install dependencies
RUN apk add --no-cache --update postfix dovecot ca-certificates git gcc musl-dev linux-headers libmilter-dev

#install python
RUN apk add --update --no-cache python3 python3-dev && ln -sf python3 /usr/bin/python
RUN python3 -m ensurepip; pip3 install --no-cache --upgrade pip setuptools

RUN pip3 install zimbraweb git+https://github.com/sdgathman/pymilter

#dovecot config
ADD ./files/dovecot/conf.d/ /etc/dovecot/conf.d/

#copy python scripts
ADD ./files/*.py /srv/zimbraweb/
RUN chmod 777 /srv/zimbraweb/*.py

RUN mkdir /srv/zimbraweb/mnt/ /srv/zimbraweb/logs/; chmod -R 777 /srv/zimbraweb/mnt/; chmod -R 777 /srv/zimbraweb/logs/

VOLUME /srv/zimbraweb/mnt/

# Add crontab to delete auth tokens from memory
RUN crontab -l /cron
RUN echo "* * * * * find /dev/shm/ -name auth_* -type f -perm 444 -mmin +3 -delete" >> /cron
RUN crontab /cron
RUN rm /cron

#postfix config
RUN postconf -e mynetworks=0.0.0.0/0; postconf -e "maillog_file=/dev/stdout"; postconf -e smtpd_sasl_path=private/auth; postconf -e smtpd_sasl_type=dovecot; postconf -e smtpd_sasl_auth_enable=yes; postconf -e smtpd_delay_reject=yes; postconf -e smtpd_client_restrictions=permit_sasl_authenticated,reject; postconf -e smtpd_milters=unix:/milter.sock

#add script execution
#https://contrid.net/server/mail-servers/postfix-catch-all-pipe-to-script
RUN touch /etc/postfix/virtual_aliases
RUN echo "*  zimbrawebtransport:" > /etc/postfix/transport
#zusammen mit -e muss bei echo $ escaped werden
RUN echo -e "zimbrawebtransport   unix  -       n       n       -       -       pipe\n  flags=FR user=nobody argv=/srv/zimbraweb/send_mail.py\n  \${nexthop} \${user} \${sasl_username}" >> /etc/postfix/master.cf
RUN echo -e "transport_maps = texthash:/etc/postfix/transport\nvirtual_alias_maps = texthash:/etc/postfix/virtual_aliases" >> /etc/postfix/main.cf

#send sender dependent relay host
RUN echo -e "relay@dhbw-mail.julian-lemmerich.de  [172.17.0.2]:25" >> /etc/postfix/relay_by_sender
RUN echo -e "sender_dependent_relayhost_maps = texthash:/etc/postfix/relay_by_sender" >> /etc/postfix/main.cf

RUN echo -e "submission inet n - y - - smtpd" >> /etc/postfix/master.cf; echo -e " -o syslog_name=postfix/submission" >> /etc/postfix/master.cf; echo -e " -o smtpd_sasl_auth_enable=yes" >> /etc/postfix/master.cf; echo -e " -o smtpd_sasl_path=private/auth" >> /etc/postfix/master.cf; echo -e " -o smtpd_client_restrictions=permit_sasl_authenticated,reject" >> /etc/postfix/master.cf

# Expose smtp submission port
EXPOSE 587

ADD ./files/start.sh /
RUN chmod +x /start.sh

ADD ./files/tls.sh /
RUN chmod +x /tls.sh; mkdir /tls/

CMD ["/start.sh"]
