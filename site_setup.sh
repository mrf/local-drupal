#!/bin/bash
if [ $(id -u) != 0 ]; then
        printf "This script must be run as root.\n"
        exit 1
fi


httpd_group='www-data'

# Help menu
print_help() {
cat <<-HELP

This script is used to set up a local Drupal installation. 
you need to provide the following arguments:

1) Path to your Drupal installation.
2) Username of the user that you want to give files/directories ownership.
3) HTTPD group name (defaults to www-data for Apache).
4) Site name.
5) Path to database export. 
5) Mysql user. 
5) Mysql pass. 

Usage: (sudo) bash ${0##*/} --drupal_path=PATH --user=USER --httpd_group=GROUP --site_name=NAME --database_path=PATH --database_user=USER --database_pass=PASSWORD

Example: (sudo) bash ${0##*/} --drupal_path=/usr/local/apache2/htdocs --user=john --httpd_group=www-data --site_name=foo --database_path=/home/john/my_import.sql --database_user=root --database_pass=mypassword

HELP
exit 0
}

# Parse Command Line Arguments
while [ $# -gt 0 ]; do
case "$1" in
  --drupal_path=*)
    drupal_path="${1#*=}"
    ;;
  --user=*)
    user="${1#*=}"
    ;;
  --httpd_group=*)
    httpd_group="${1#*=}"
    ;;
  --site_name=*)
    site_name="${1#*=}"
    ;;
  --database_path=*)
    database_path="${1#*=}"
    ;;
  --database_user=*)
    database_user="${1#*=}"
    ;;
  --database_pass=*)
    database_pass="${1#*=}"
    ;;
  --help) 
    print_help
    ;;
  *)
  printf "Invalid argument, run --help for valid arguments.\n";
  exit 1
esac
shift
done

echo $user
echo $httpd_group
echo $drupal_path
echo $database_pass
echo $database_path

if [ -z "${drupal_path}" ] || [ ! -d "${drupal_path}/sites" ] || [ ! -f "${drupal_path}/core/modules/system/system.module" ] && [ ! -f "${drupal_path}/modules/system/system.module" ]; then
printf "Please provide a valid Drupal path.\n"
print_help
exit 1
fi

if [ -z "${user}" ] || [ $(id -un ${user} 2> /dev/null) != "${user}" ]; then
printf "Please provide a valid user.\n"
print_help
exit 1
fi

#TODO Validate other parameters

cd /etc/nginx/sites-available
cp template.dev $site_name.dev
sed -i "s|SITE_NAME|$site_name|g" /etc/nginx/sites-available/$site_name.dev
sed -i "s|DRUPAL_PATH|$drupal_path|g" /etc/nginx/sites-available/$site_name.dev


#cat /etc/nginx/sites-available/$site_name.dev
echo "Site alias created"


#edit /etc/hosts to add 127.0.0.1 sitename.dev
# TODO check if already exists
echo 127.0.0.1 $site_name.dev >> /etc/hosts

echo "Site added to hosts file"

ln -s /etc/nginx/sites-available/$site_name.dev /etc/nginx/sites-enabled/$site_name.dev

/etc/init.d/nginx restart


mysql -u $database_user -p $database_pass -e "create database $site_name;"
wait

pv $database_path | mysql -u $database_user -p $database_pass $site_name


cd $drupal_path

#create sitename local dev folder
mkdir sites/$site_name.dev
mkdir sites/$site_name.dev/files
ln -s sites/$site_name.dev/files sites/default/files
cp sites/default/default.settings.php sites/$site_name.dev/settings.php

echo "\$databases['default']['default'] = array('driver' => 'mysql','database' => '$site_name','username' => 'foobar','password' => '','host' => 'localhost',);" >> sites/$site_name.dev/settings.php


#run file permission setting script
printf "Changing ownership of all contents of \"${drupal_path}\":\n user => \"${user}\" \t group => \"${httpd_group}\"\n"
chown -R ${user}:${httpd_group} .

printf "Changing permissions of all directories inside \"${drupal_path}\" to \"rwxr-x---\"...\n"
find . -type d -exec chmod u=rwx,g=rx,o= '{}' \;

printf "Changing permissions of all files inside \"${drupal_path}\" to \"rw-r-----\"...\n"
find . -type f -exec chmod u=rw,g=r,o= '{}' \;

printf "Changing permissions of \"files\" directories in \"${drupal_path}/sites\" to \"rwxrwx---\"...\n"
cd ${drupal_path}/sites
find . -type d -name files -exec chmod ug=rwx,o= '{}' \;
printf "Changing permissions of all files inside all \"files\" directories in \"${drupal_path}/sites\" to \"rw-rw----\"...\n"
printf "Changing permissions of all directories inside all \"files\" directories in \"${drupal_path}/sites\" to \"rwxrwx---\"...\n"

for x in ./*/files; do
find ${x} -type d -exec chmod ug=rwx,o= '{}' \;
find ${x} -type f -exec chmod ug=rw,o= '{}' \;
done

echo "Done settings proper permissions on files and directories"


#TODO Create drush alias and use it to test our site

echo "You are ready to go"
