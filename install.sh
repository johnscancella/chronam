#!/usr/bin/env bash

MY_SQL_PASSWORD=password

output(){
echo -en '\E[31m'"\033[1m$1\033[0m"
tput sgr0
}

# from http://stackoverflow.com/a/246128/971169
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# stop the script if a command does not return normally
set -e

#setup apt-get so it will use a password when installing mysql
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MY_SQL_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MY_SQL_PASSWORD"

#add the java repo for java 8
sudo add-apt-repository ppa:openjdk-r/ppa -y
sudo apt-get update

#Install system level dependencies
sudo apt-get install python-dev python-virtualenv mysql-server libmysqlclient-dev apache2 libapache2-mod-wsgi openjdk-8-jdk libxml2-dev libxslt-dev libjpeg-dev git-core graphicsmagick -y


#get chronam
if [ ! -d /opt/chronam ]
then
  sudo mkdir /opt/chronam
  sudo chown $USER:users /opt/chronam
  git clone $SCRIPT_DIR /opt/chronam
else
  output "/opt/chronam already exists, so skipping cloning chronam."
  sudo chown $USER:users /opt/chronam
fi

#configure Solr
if [ ! -d /opt/solr ]
then
  if [ ! -f solr-4.10.4.tgz ]
  then
    wget http://archive.apache.org/dist/lucene/solr/4.10.4/solr-4.10.4.tgz
  else
    output "solr-4.10.4.tgz already exists. Skipping downloading solr 4.10.4."
  fi
  tar zxvf solr-4.10.4.tgz
  sudo mv solr-4.10.4/example/ /opt/solr
else
  output "/opt/solr already exists. Skipping downloading solr 4.10.4."
fi

if ! id solr >/dev/null 2>&1
then
  sudo useradd -d /opt/solr -s /bin/bash solr
else
  output "user solr already exists, skipping creating solr user"
fi
sudo chown solr:solr -R /opt/solr

sudo cp /opt/chronam/conf/jetty7.sh /etc/init.d/jetty
sudo chmod +x /etc/init.d/jetty

sudo cp /opt/chronam/conf/schema.xml /opt/solr/solr/collection1/conf/schema.xml
sudo cp /opt/chronam/conf/solrconfig.xml /opt/solr/solr/collection1/conf/solrconfig.xml

sudo cp /opt/chronam/conf/jetty-ubuntu /etc/default/jetty
sudo service jetty start

#configure apache
sudo a2enmod cache expires rewrite cache_disk
sudo cp /opt/chronam/conf/chronam.conf /etc/apache2/sites-available/chronam.conf
sudo a2ensite chronam
sudo install -o $USER -g users -d /opt/chronam/static
sudo install -o $USER -g users -d /opt/chronam/.python-eggs
sudo service apache2 reload

#setup python environment
cd /opt/chronam/
if [ ! -d ENV ]
then
  virtualenv -p python2.7 ENV
else
  output "/opt/chronam/ENV already exists, skipping creating virtual environment for python"
fi
source /opt/chronam/ENV/bin/activate
cp conf/chronam.pth ENV/lib/python2.7/site-packages/chronam.pth
pip install -r requirements.pip

#make data directories
mkdir -p /opt/chronam/data/batches
mkdir -p /opt/chronam/data/cache
mkdir -p /opt/chronam/data/bib

#create mysql database
sudo service mysql restart
sudo mysqladmin -u root password "MY_SQL_PASSWORD"

echo "DROP DATABASE IF EXISTS chronam; CREATE DATABASE chronam CHARACTER SET utf8; GRANT ALL ON chronam.* to 'chronam'@'localhost' identified by 'pick_one'; GRANT ALL ON test_chronam.* to 'chronam'@'localhost' identified by 'pick_one';" | mysql -u root -p$MY_SQL_PASSWORD

cp /opt/chronam/settings_template.py /opt/chronam/settings.py

#initialize database
export DJANGO_SETTINGS_MODULE=chronam.settings
django-admin.py migrate
django-admin.py loaddata initial_data
django-admin.py chronam_sync --skip-essays
django-admin.py collectstatic --noinput

#load NDNP data
cd /opt/chronam/data
wget --recursive --no-host-directories --cut-dirs 1 --reject index.html* --include-directories /data/batches/batch_uuml_thys_ver01/ http://chroniclingamerica.loc.gov/data/batches/batch_uuml_thys_ver01/
django-admin.py load_batch /opt/chronam/data/batches/batch_uuml_thys_ver01

sudo service httpd restart
