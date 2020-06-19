#!/bin/bash
set -e

if [[ -z $smtp_user ]]
then
cat << EOF > /etc/msmtprc
account default
host ${smtp_host}
port ${smtp_port}
from ${from_address}
logfile /var/log/msmtp.log
EOF

else
cat << EOF > /etc/msmtprc
account default
host ${smtp_host}
port ${smtp_port}
tls on
tls_starttls on
tls_certcheck off
auth on
user ${smtp_user}
password ${smtp_pass}
from ${from_address}
logfile /var/log/msmtp.log
EOF
fi
chmod 600 /etc/msmtprc

echo "Running Summary Report..."
/usr/bin/systems_summary.sh | tee report.txt

echo "To: ${to_address}" > email.txt
if [[ "$send_to_support" == "true" ]]
then
  echo "CC: support@support.tools" >> email.txt
fi
echo "From: ${from_address}" >> email.txt
echo "Subject: Rancher Systems Summary Report - ${rancher_name}" >> email.txt
cat report.txt >> email.txt
cat email.txt | msmtp -a default ${to_address}
