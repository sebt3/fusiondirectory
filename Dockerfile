FROM php:7.1-fpm-alpine
ENV FD_VERSION 1.3
ENV I18N_VERSION 1.0
ENV CAS_VERSION 1.3.8
ENV SMARTY_VERSION 3.1.34
ENV FPDF_VERSION 182
ENV SAUS_VERSION 1.8.3
RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/testing>>/etc/apk/repositories \
 && sed -i 's/dl-cdn.alpinelinux.org/ftp.halifax.rwth-aachen.de/g' /etc/apk/repositories \
 && apk --update --no-cache --no-progress add libpng imagemagick-libs libjpeg-turbo tzdata libldap libmcrypt krb5 imap libintl c-client openldap-clients openldap gettext imagemagick \
 && apk --update --no-progress add --virtual build-deps autoconf curl-dev freetype-dev build-base libjpeg-turbo-dev imagemagick-dev libmcrypt-dev libpng-dev libtool libxml2-dev openldap-dev unzip libmcrypt-dev krb5-dev imap-dev icu-dev  gettext-dev \
 && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
 && docker-php-ext-configure gd --with-freetype-dir=/usr --with-png-dir=/usr --with-jpeg-dir=/usr \
 && docker-php-ext-install gd json mbstring xml zip mcrypt curl json xml zip imap gettext ldap \
 && pecl install imagick                \
 && docker-php-ext-enable imagick       \
 && sed -i '/www-data/s#:[^:]*$#:/bin/ash#' /etc/passwd \
 && curl -sL https://github.com/apereo/phpCAS/releases/download/${CAS_VERSION}/CAS-${CAS_VERSION}.tgz>/tmp/CAS.tgz \
 && pear install /tmp/CAS.tgz \
 && mkdir /usr/local/lib/php/fpdf \
 && echo "http://www.fpdf.org/fr/dl.php?v=${FPDF_VERSION}&f=tgz" \
 && curl -sL "http://www.fpdf.org/fr/dl.php?v=${FPDF_VERSION}&f=tgz" |tar xz -C /tmp \
 && mv /tmp/fpdf${FPDF_VERSION}/f* /usr/local/lib/php/fpdf \
 && ln -sf fpdf/fpdf.php /usr/local/lib/php/fpdf.php \
 && echo https://github.com/smarty-php/smarty/archive/v${SMARTY_VERSION}.tar.gz \
 && curl -sL https://github.com/smarty-php/smarty/archive/v${SMARTY_VERSION}.tar.gz|tar xz --strip 1 -C /tmp \
 && mv /tmp/libs/ /usr/local/lib/php/smarty3 \
 && echo -e 'expose_php = Off;\nimplicit_flush = Off;\nmemory_limit = 128M ;\nmax_execution_time = 60 ;\nsession.auto_start = off ;' > /usr/local/etc/php/conf.d/fusiondirectory.ini \
 && apk --purge del build-deps \
 && rm -rf /tmp/* \
 \
 && curl -sL "https://repos.fusiondirectory.org/sources/smarty3-i18n/smarty3-i18n-${I18N_VERSION}.tar.gz" |tar xz --wildcards --strip 1 -C /usr/local/lib/php/smarty3/plugins/ */*.php \
 && apk --update --no-cache --no-progress add perl-path-class perl-xml-twig perl-file-copy-recursive perl-crypt-cbc perl-mime-base64 perl-ldap perl-archive-extract perl-term-readkey \
 && curl -sL "https://repos.fusiondirectory.org/sources/schema2ldif/schema2ldif-${FD_VERSION}.tar.gz" |tar xz --strip 1 -C /tmp && mv /tmp/bin/* /usr/bin \
 && mkdir /fusiondirectory \
 && curl -sL "https://repos.fusiondirectory.org/sources/fusiondirectory/fusiondirectory-${FD_VERSION}.tar.gz" | tar xz --strip 1 -C /fusiondirectory \
 && curl -sL "https://repos.fusiondirectory.org/sources/fusiondirectory/fusiondirectory-plugins-${FD_VERSION}.tar.gz" >/usr/share/fusiondirectory-plugins-${FD_VERSION}.tar.gz \
 && curl -sL "http://script.aculo.us/dist/scriptaculous-js-${SAUS_VERSION}.tar.gz"|tar xz --strip 2 -C /fusiondirectory/html/include \
 && rm -f /fusiondirectory/html/include/*html \
 && cp /fusiondirectory/contrib/smarty/plugins/function.msgPool.php /fusiondirectory/contrib/smarty/plugins/function.filePath.php /usr/local/lib/php/smarty3/plugins/ \
 && chmod 755 /fusiondirectory/contrib/bin/f* && mv /fusiondirectory/contrib/bin/f* /usr/bin/ \
 && ln -s /usr/local/lib/php /usr/share/php \
 && mkdir -p /var/cache/fusiondirectory/fai /var/cache/fusiondirectory/tmp /var/cache/fusiondirectory/template /var/spool/fusiondirectory /etc/fusiondirectory \
 && chown root:www-data /var/cache/fusiondirectory /var/cache/fusiondirectory/fai /var/cache/fusiondirectory/tmp /var/cache/fusiondirectory/template /var/spool/fusiondirectory \
 && chmod 770  /var/cache/fusiondirectory /var/cache/fusiondirectory/fai /var/cache/fusiondirectory/tmp /var/cache/fusiondirectory/template /var/spool/fusiondirectory \
 && mkdir -p /etc/ldap/schema \
 && ln -s /var/web/contrib/openldap/ /etc/ldap/schema/fusiondirectory \
 && sed -i 's#define("SMARTY".*#define("SMARTY", "/usr/local/lib/php/smarty3/Smarty.class.php");#' /fusiondirectory/include/variables.inc \
 && cp /fusiondirectory/contrib/smarty/plugins/* /usr/local/lib/php/smarty3/plugins/ \
 && cp /fusiondirectory/contrib/fusiondirectory.conf /var/cache/fusiondirectory/template/ \
 && echo "${FD_VERSION}">/fusiondirectory/version \
 && rm -rf /tmp/*

COPY entrypoint.sh /bin
ENTRYPOINT [ "/bin/entrypoint.sh" ]
CMD ["php-fpm"]
VOLUME /var/web
