# 编译ONLYOFFICE并打包镜像说明

本文档介绍如何使用 Docker 容器编译 ONLYOFFICE，并将其打包成 deb 包和 Docker 镜像。

## 整体步骤
1. 构建编译环境镜像
2. 编译服务
3. 打包 deb 包
4. 打包 docker 镜像

## 详细步骤说明

### 1. 构建编译环境镜像

编译环境使用 Ubuntu 22.04 作为基础镜像，包含了所有必要的编译依赖。使用以下命令构建：

```bash
docker build -f Dockerfile_compile -t onlyoffice-document-builder .
```

### 2. 编译服务

使用编译环境镜像进行编译：

```bash
docker run --rm \
    -e BUILD_MODULES= \
    -e BUILD_VERSION=8.2.0 \
    -e PRODUCT_VERSION=8.2.0 \
    -e BUILD_NUMBER=199 \
    -v /onlyoffice:/onlyoffice \
    onlyoffice-document-builder
# bebug版本
docker run --rm \
    -e BUILD_MODULES= \
    -e BUILD_VERSION=8.2.0 \
    -e PRODUCT_VERSION=8.2.0 \
    -e BUILD_NUMBER=182 \
    -v /onlyoffice:/onlyoffice \
    onlyoffice-document-builder \
    -c "cd tools/linux && python ./automate.py --config=debug"    
```

参数说明：
- BUILD_MODULES: 编译模块，可选值：desktop、builder、server，默认全部编译
- BUILD_VERSION: 版本号
- PRODUCT_VERSION: 产品版本号
- BUILD_NUMBER: 构建编号
- -v /onlyoffice:/onlyoffice: 挂载源码目录

#### 编译注意事项

1. 源代码修改
编译前需要对以下源代码文件进行修改：

a) 添加 cmath 头文件，在以下文件开头添加 `#include <cmath>`:
```cpp
// desktop-sdk/ChromiumBasedEditors/videoplayerlib/src/qtimelabel.cpp
#include <QFontMetrics>
#include <QtGlobal>
#include <cmath>
```

```cpp
// desktop-sdk/ChromiumBasedEditors/videoplayerlib/src/qvideoslider.cpp
#include <QStyleOption>
#include <QPainter>
#include <cmath>
```

```cpp
// desktop-sdk/ChromiumBasedEditors/videoplayerlib/src/qvideoplaylist.cpp
#include <QStandardPaths>
#include <QShortcut>
#include <cmath>
```

这些修改是为了解决编译时 `fabs()` 函数未定义的错误。`fabs()` 函数用于计算浮点数的绝对值,定义在 cmath 头文件中。

b) qt_build 相关修改：
- 编译时会自动下载并编译 qt 库
- 需要修改 qt 源码文件：`qt-everywhere-opensource-src-5.9.9/qtbase/src/corelib/tools/qbytearray.h`
  - 添加 `#include <limits>`

c) hunspell 库修改：
- 修改文件 `/onlyoffice/core/Common/3dParty/hunspell/hunspell.json`
- 将文件中的双引号替换为单引号

2. 文体包

需要将biyue字体放在 `/onlyoffice/core-fonts/` 

### 3. 打包 deb 包

使用以下命令将编译好的服务打包成 deb 包：

```bash
docker run --rm \
    -e BUILD_MODULES= \
    -e BUILD_VERSION=8.2.0 \
    -e PRODUCT_VERSION=8.2.0 \
    -e BUILD_NUMBER=183 \
    -v /onlyoffice:/onlyoffice \
    onlyoffice-document-builder \
    -c "cd ../document-server-package && make clean && make deb"
```

打包完成后，deb 包将保存在 `document-server-package/deb` 目录下。

#### 打包注意事项

1. 复制 api.js.tpl 文件到 api.js
make过程会复制，但是编译时生成的是api.js.tpl，需要手动复制到api.js
```bash
cd /onlyoffice/build_tools/out/linux_64/onlyoffice/documentserver/web-apps/apps/api/documents
cp api.js.tpl api.js
```


### 4. 打包 docker 镜像

将生成的 deb 包打包成最终的 docker 镜像：

```bash
export BUILD_VERSION=8.2.0
export PRODUCT_VERSION=8.2.0
export BUILD_NUMBER=183

cd ../Docker-DocumentServer
cp ../document-server-package/deb/*.deb ./

DOCKER_TAG=$BUILD_VERSION-$BUILD_NUMBER
docker build . -t nicedoc-documentserver:$DOCKER_TAG \
    --build-arg PACKAGE_VERSION=$BUILD_VERSION-$BUILD_NUMBER
docker tag nicedoc-documentserver:$DOCKER_TAG nicedoc-documentserver:latest
```

## 环境依赖

如果需要在本地编译（不使用 Docker），需要安装以下依赖：

### Ubuntu/Debian 系统:
```bash
sudo apt-get install libgtk-3-dev libxkbcommon-dev libxkbcommon-x11-dev
```

### CentOS/RHEL 系统:
```bash
sudo yum install gtk3-devel libxkbcommon-devel libxkbcommon-x11-devel
```

### Fedora 系统:
```bash
sudo dnf install gtk3-devel libxkbcommon-devel libxkbcommon-x11-devel
```

