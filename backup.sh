#!/bin/bash

colors=( "\033[1;31m" "\033[1;92m" "\033[1;36m" "\033[1;33m" "\033[0m" )
red=${colors[0]} green=${colors[1]} cyan=${colors[2]} yellow=${colors[3]} reset=${colors[4]}
print() { echo -e "${cyan}$1${reset}"; }
error() { echo -e "${red}✗ $1${reset}"; }

while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

while [[ -z "$chatids" ]]; do
    echo "Chat IDs (comma-separated, e.g., -1001234567890,-1009876543210): "
    read -r chatids
    if [[ $chatids == $'\0' ]]; then
        echo "Invalid input. Chat IDs cannot be empty."
        unset chatids
    else
        IFS=',' read -ra chatid_array <<< "$chatids"
        valid=true
        for chatid in "${chatid_array[@]}"; do
            chatid=$(echo "$chatid" | tr -d '[:space:]')
            if [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
                echo "${chatid} is not a valid number."
                valid=false
                break
            fi
        done
        if [[ "$valid" == "false" ]]; then
            unset chatids
        fi
    fi
done

echo "Caption (e.g., your domain, to identify the database file): "
read -r caption

while true; do
    echo "Cronjob (minutes and hours, e.g., 30 6 or 0 12): "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} */${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (e.g., 0 6 or 30 12)"
    fi
done

while [[ -z "$xmh" ]]; do
    echo "x-ui or marzban or hiddify? [x/m/h]: "
    read -r xmh
    if [[ $xmh == $'\0' ]]; then
        echo "Invalid input. Please choose x, m, or h."
        unset xmh
    elif [[ ! $xmh =~ ^[xmh]$ ]]; then
        echo "${xmh} is not a valid option. Please choose x, m, or h."
        unset xmh
    fi
done

while [[ -z "$crontabs" ]]; do
    echo "Would you like the previous crontabs to be cleared? [y/n]: "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
    sudo crontab -l | grep -vE '/root/backup\.sh' | crontab -
fi

if [[ "$xmh" == "m" ]]; then
    if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
        print "The folder exists at $dir"
    else
        error "The folder does not exist."
        exit 1
    fi

    if [ -d "/var/lib/marzban/mysql" ]; then
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env
        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
        source /opt/marzban/.env
        cat > "/var/lib/marzban/mysql/ac-backup.sh" <<EOL
#!/bin/bash
USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"
databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]]; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
        chmod +x /var/lib/marzban/mysql/ac-backup.sh
        ZIP=$(cat <<EOF
docker exec marzban-mysql-1 bash -c "/var/lib/mysql/ac-backup.sh"
zip -r /root/backup.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/\*
zip -r /root/backup.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
)
        backup_type="Marzban backup"
    else
        ZIP="zip -r /root/backup.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
        backup_type="Marzban backup"
    fi
elif [[ "$xmh" == "x" ]]; then
    if dbDir=$(find /etc /opt/freedom -type d -iname "x-ui*" -print -quit); then
        print "The folder exists at $dbDir"
        if [[ $dbDir == *"/opt/freedom/x-ui"* ]]; then
            dbDir="${dbDir}/db/"
        fi
    else
        error "The folder does not exist."
        exit 1
    fi
    if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
        print "The folder exists at $configDir"
    else
        error "The folder does not exist."
        exit 1
    fi
    ZIP="zip /root/backup.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    backup_type="X-UI backup"
elif [[ "$xmh" == "h" ]]; then
    if ! find /opt/hiddify-manager/hiddify-panel/ -type d -iname "backup" -print -quit; then
        error "The folder does not exist."
        exit 1
    fi
    ZIP=$(cat <<EOF
cd /opt/hiddify-manager/hiddify-panel/
if [ \$(find /opt/hiddify-manager/hiddify-panel/backup -type f | wc -l) -gt 100 ]; then
    find /opt/hiddify-manager/hiddify-panel/backup -type f -delete
fi
python3 -m hiddifypanel backup
cd /opt/hiddify-manager/hiddify-panel/backup
latest_file=\$(ls -t *.json | head -n1)
rm -f /root/backup.zip
zip /root/backup.zip /opt/hiddify-manager/hiddify-panel/backup/\$latest_file
EOF
)
    backup_type="Hiddify backup"
else
    error "Please choose m, x, or h only!"
    exit 1
fi

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\n${backup_type}\n<code>${IP}</code>\nCreated by mahyyar - https://github.com/mahyyar/backup"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=$(trim "$comment")

print "Installing zip..."
sudo apt install zip -y > /dev/null 2>&1 || { error "Failed to install zip"; exit 1; }
print "done"

print "Creating backup..."
cat > "/root/backup.sh" <<EOL
#!/bin/bash
rm -rf /root/backup.zip
$ZIP
echo -e "$comment" | zip -z /root/backup.zip
for chatid in ${chatid_array[*]}; do
    curl -F chat_id="\${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/root/backup.zip" https://api.telegram.org/bot${tk}/sendDocument
done
EOL
chmod +x /root/backup.sh
bash "/root/backup.sh"
print "done"

{ crontab -l -u root; echo "${cron_time} /bin/bash /root/backup.sh >/dev/null 2>&1"; } | crontab -u root -

print "Done"
