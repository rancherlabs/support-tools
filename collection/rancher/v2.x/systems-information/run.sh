#!/bin/bash
set -e

if [[ -z $SMTP_USER ]]
then
cat << EOF > /etc/msmtprc
account default
host ${SMTP_HOST}
port ${SMTP_PORT}
from ${FROM_ADDRESS}
logfile /var/log/msmtp.log
EOF

else
cat << EOF > /etc/msmtprc
account default
host ${SMTP_HOST}
port ${SMTP_PORT}
tls on
tls_starttls on
tls_certcheck off
auth on
user ${SMTP_USER}
password ${SMTP_PASS}
from ${FROM_ADDRESS}
logfile /var/log/msmtp.log
EOF
fi
chmod 600 /etc/msmtprc

echo "Running Summary Report..."
/usr/bin/systems_summary.sh | tee report.txt

echo "To: ${TO_ADDRESS}" > email.txt
echo "CC: support@support.tools" >> email.txt
echo "From: ${FROM_ADDRESS}" >> email.txt
echo "Subject: Rancher Systems Summary Report - ${RANCHER_NAME}" >> email.txt
cat report.txt >> email.txt
cat email.txt | msmtp -a default ${TO_ADDRESS}
