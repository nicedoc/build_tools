#!/bin/sh
if true; then
cd ../core
git pull
cd ../sdkjs/
git pull
cd ../core
git pull
cd ../web-apps
git pull
cd ../onlyoffice.github.io
git pull
cd ../build_tools

# add build num
sed -E 's/([0-9]+)/echo "$((\1+1))"|bc/e' build_number  | sponge build_number
export BUILD_VERSION=`cat version`
export PRODUCT_VERSION=$BUILD_VERSION
export BUILD_NUMBER=`cat build_number`
python3 make.py

cd ../document-server-package
make clean
make deb
fi
cd ../Docker-DocumentServer
cp ../document-server-package/deb/*.deb ./
DOCKER_TAG=$BUILD_VERSION-$BUILD_NUMBER
docker build . -t nicedoc-documentserver:$DOCKER_TAG \
	--build-arg PACKAGE_VERSION=$BUILD_VERSION-$BUILD_NUMBER
docker tag nicedoc-documentserver:$DOCKER_TAG nicedoc-documentserver:latest
#echo "stop old container"
#sudo docker stop nicedoc-example
#echo "remove old container"
#sudo docker rm nicedoc-example
#echo "start new container"

docker tag nicedoc-documentserver registry.nicedoc.cn/nicedoc-documentserver
docker tag nicedoc-documentserver:$DOCKER_TAG registry.nicedoc.cn/nicedoc-documentserver:$DOCKER_TAG
cd ~/registry
docker-compose --project-directory ~/registry up -d
sleep 10
docker exec onlyoffice sudo supervisorctl start ds:example
sleep 10
docker push registry.nicedoc.cn/nicedoc-documentserver:latest
docker push registry.nicedoc.cn/nicedoc-documentserver:$DOCKER_TAG