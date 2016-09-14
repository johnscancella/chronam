#!/usr/bin/env bash

#setup apt-get so it will use a password when installing mysql
#sudo debconf-set-selection <<< 'mysql-server mysql-server/root_password password password'
#sudo debconf-set-selection <<< 'mysql-server mysql-server/root_password_again password password'

#Install system level dependencies
sudo apt-get install python-dev python-virtualenv mysql-server libsqlclient-dev apache2 libapache2-mod-wsgi openjdk-8-jdk libxml2-dev libxslt-dev libjpeg-dev git-core graphicsmagick -y

#get chronam
if [ ! -d /opt/chronam ]
then
  sudo mkdir /opt/chronam
  sudo chown $USER:users /opt/chronam
  git clone https://github.com/LibraryOfCongress/chronam.git /opt/chronam
else
  echo "/opt/chronam already exists, so skipping cloning chronam."
  sudo chown $USER:users /opt/chronam
fi

#configure Solr
if [ ! -d /opt/solr ]
then
  if [ ! -f solr-4.10.4.tgz ]
  then
    wget http://archive.apache.org/dist/lucene/solr/4.10.4/solr-4.10.4.tgz
  else
    echo "solr-4.10.4.tgz already exists. Skipping downloading solr 4.10.4."
  fi
  tar zxvf solr-4.10.4.tgz
  sudo mv solr-4.10.4/example/ /opt/solr
else
  echo "/opt/solr already exists. Skipping downloading solr 4.10.4."
fi

if ! id solr >/dev/null 2>%1
then
  sudo useradd -d /opt/solr -s /bin/bash solr
else
  echo "user solr already exists, skipping creating solr user"
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
sudo cp /opt/chronam/conf/chronam.conf /etc/apache2/sites-available/chronam
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
  echo "/opt/chronam/ENV already exists, skipping creating virtual environment for python"
fi
source /opt/chronam/ENV/bin/activate
cp conf/chronam.pth ENV/lib/python2.7/site-packages/chronam.pth
pip install -r requirements.pip

#make data directories
mkdir -p /opt/chronam/data/batches
mkdir -p /opt/chronam/data/cache
mkdir -p /opt/chronam/data/bib

#create mysql database
sudo service mysql start
sudo mysqladmin -u root password 'password'

#TODO DEBUG
exit 1
echo "DROP DATABASE IF EXISTS chronam; CREATE DATABASE chronam CHARACTER SET utf8; GRANT ALL ON chronam.* to 'chronam'@'localhost' identified by 'pick_one'; GRANT ALL ON test_chronam.* to 'chronam'@'localhost' identified by 'pick_one';" | mysql -u root -p

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
