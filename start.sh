wget https://github.com/glebsterx/OpenLumiScripts/archive/refs/heads/main.tar.gz -O /tmp/OpenLumi.tar.gz
mkdir -p /tmp/OpenLumi
tar -xvzf /tmp/OpenLumi.tar.gz -C /tmp/OpenLumi
mv /tmp/OpenLumi/OpenLumiScripts-main/* /tmp/OpenLumi/
rm -rf /tmp/OpenLumi/OpenLumiScripts-main
/tmp/OpenLumi/setup.sh
