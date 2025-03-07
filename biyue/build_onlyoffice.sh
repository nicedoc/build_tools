#!/bin/bash

# 设置错误时退出
set -e

# 记录开始时间
START_TIME=$(date +%s)

# 全局路径配置
ONLYOFFICE_ROOT="/onlyoffice"
CORE_DIR="$ONLYOFFICE_ROOT/core"
SDKJS_DIR="$ONLYOFFICE_ROOT/sdkjs"
WEB_APPS_DIR="$ONLYOFFICE_ROOT/web-apps"
GITHUB_IO_DIR="$ONLYOFFICE_ROOT/onlyoffice.github.io"
BUILD_TOOLS_DIR="$ONLYOFFICE_ROOT/build_tools"
DOCKER_SERVER_DIR="$ONLYOFFICE_ROOT/Docker-DocumentServer"
DOC_SERVER_PACKAGE_DIR="$ONLYOFFICE_ROOT/document-server-package"
EXAMPLE_DIR="/opt/onlyoffice/"

# 全局变量定义
BUILD_VERSION=""
PRODUCT_VERSION=""
BUILD_NUMBER=""

# 计算执行时间的函数
calculate_time() {
    local end_time=$(date +%s)
    local time_taken=$((end_time - START_TIME))
    local hours=$((time_taken / 3600))
    local minutes=$(( (time_taken % 3600) / 60 ))
    local seconds=$((time_taken % 60))
    echo "总执行时间: ${hours}小时 ${minutes}分钟 ${seconds}秒"
}

# 1. 更新代码
update_code() {
    echo "正在更新代码..."
    cd "$CORE_DIR" && git pull
    cd "$SDKJS_DIR" && git pull
    cd "$WEB_APPS_DIR" && git pull
    cd "$GITHUB_IO_DIR" && git pull
    cd "$ONLYOFFICE_ROOT"
}

# 2. 设置版本信息
setup_version() {
    echo "设置版本信息..."
    # 增加构建号
    sed -E 's/([0-9]+)/echo "$((\1+1))"|bc/e' build_number | sponge build_number
    
    # 设置全局变量
    BUILD_VERSION=$(cat version)
    PRODUCT_VERSION=$BUILD_VERSION
    BUILD_NUMBER=$(cat build_number)
    
    # 导出环境变量，确保子进程可以访问
    export BUILD_VERSION
    export PRODUCT_VERSION
    export BUILD_NUMBER
    
    echo "当前版本: $BUILD_VERSION"
    echo "构建号: $BUILD_NUMBER"
}

# 3. 编译服务
compile_service() {
    echo "开始编译服务..."
    local start_time=$(date +%s)
    
    # 添加参数判断是否为debug模式
    if [ "$1" = "debug" ]; then
        echo "使用debug模式编译..."
        docker run --rm \
            -e BUILD_MODULES= \
            -e BUILD_VERSION=$BUILD_VERSION \
            -e PRODUCT_VERSION=$PRODUCT_VERSION \
            -e BUILD_NUMBER=$BUILD_NUMBER \
            -v $ONLYOFFICE_ROOT:/onlyoffice \
            onlyoffice-document-builder \
            -c "cd tools/linux && python ./automate.py --config=debug"
    else
        docker run --rm \
            -e BUILD_MODULES= \
            -e BUILD_VERSION=$BUILD_VERSION \
            -e PRODUCT_VERSION=$PRODUCT_VERSION \
            -e BUILD_NUMBER=$BUILD_NUMBER \
            -v $ONLYOFFICE_ROOT:/onlyoffice \
            onlyoffice-document-builder
    fi
    
    local end_time=$(date +%s)
    local time_taken=$((end_time - start_time))
    echo "编译服务耗时: $time_taken 秒"
}

# 4. 处理编译后的文件
post_compile() {
    echo "处理编译后的文件..."
    local api_dir="$BUILD_TOOLS_DIR/out/linux_64/onlyoffice/documentserver/web-apps/apps/api/documents"
    cd "$api_dir"
    cp api.js.tpl api.js
    cd "$ONLYOFFICE_ROOT"
}

# 5. 打包 deb 包
build_deb() {
    echo "打包 deb 包..."
    local start_time=$(date +%s)
    
    docker run --rm \
        -e BUILD_MODULES= \
        -e BUILD_VERSION=$BUILD_VERSION \
        -e PRODUCT_VERSION=$PRODUCT_VERSION \
        -e BUILD_NUMBER=$BUILD_NUMBER \
        -v $ONLYOFFICE_ROOT:/onlyoffice \
        onlyoffice-document-builder \
        -c "cd ../document-server-package && make clean && make deb"
    
    local end_time=$(date +%s)
    local time_taken=$((end_time - start_time))
    echo "打包 deb 耗时: $time_taken 秒"
}

# 6. 构建 Docker 镜像
build_docker_image() {
    echo "构建 Docker 镜像..."
    local start_time=$(date +%s)
    
    cd "$DOCKER_SERVER_DIR"
    cp "$DOC_SERVER_PACKAGE_DIR/deb/"*.deb ./
    
    DOCKER_TAG=$BUILD_VERSION-$BUILD_NUMBER
    docker build . -t nicedoc-documentserver:$DOCKER_TAG \
        --build-arg PACKAGE_VERSION=$BUILD_VERSION-$BUILD_NUMBER
    docker tag nicedoc-documentserver:$DOCKER_TAG nicedoc-documentserver:latest
    
    # 标记镜像并推送到私有仓库
    docker tag nicedoc-documentserver registry.nicedoc.cn/nicedoc-documentserver
    docker tag nicedoc-documentserver:$DOCKER_TAG registry.nicedoc.cn/nicedoc-documentserver:$DOCKER_TAG
    
    local end_time=$(date +%s)
    local time_taken=$((end_time - start_time))
    echo "构建 Docker 镜像耗时: $time_taken 秒"
}

# 7. 启动注册表服务并推送镜像
push_to_registry() {
    echo "推送镜像到私有仓库..."
    local start_time=$(date +%s)
    
    cd "$EXAMPLE_DIR"
    docker-compose --project-directory "$EXAMPLE_DIR" up -d
    sleep 10
    docker exec onlyoffice sudo supervisorctl start ds:example
    sleep 10
    docker push registry.nicedoc.cn/nicedoc-documentserver:latest
    docker push registry.nicedoc.cn/nicedoc-documentserver:$DOCKER_TAG
    
    local end_time=$(date +%s)
    local time_taken=$((end_time - start_time))
    echo "推送镜像耗时: $time_taken 秒"
}

# 主流程
main() {
    echo "开始 ONLYOFFICE 编译打包流程..."
    echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 检查命令行参数
    BUILD_TYPE="release"
    if [ "$1" = "debug" ]; then
        BUILD_TYPE="debug"
        echo "使用debug模式编译"
    fi
    
    update_code
    setup_version
    compile_service $BUILD_TYPE
    post_compile
    build_deb
    build_docker_image
    push_to_registry
    
    echo "ONLYOFFICE 编译打包流程完成！"
    echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    calculate_time
}

# 执行主流程
main "$@" 