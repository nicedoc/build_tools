#!/bin/bash

# 设置错误时退出，但在push_to_registry函数中临时禁用
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

# Docker镜像仓库配置
REGISTRY_HOST="reg-internal.xmdas-link.com/oo"
REGISTRY2_HOST="registry.cn-shenzhen.aliyuncs.com/biyue"
REGISTRY_IMAGE="nicedoc-documentserver"
REGISTRY_URL="$REGISTRY_HOST/$REGISTRY_IMAGE"
REGISTRY2_URL="$REGISTRY2_HOST/$REGISTRY_IMAGE"

# 全局变量定义
BUILD_VERSION=""
PRODUCT_VERSION=""
BUILD_NUMBER=""

# 添加日志相关配置
LOG_DIR="/var/log/onlyoffice/build"
LOG_FILE="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_LOG="$LOG_DIR/build_summary_$(date +%Y%m%d_%H%M%S).log"
CURRENT_SUMMARY_LINK="$LOG_DIR/current_build_summary.log"
CURRENT_LOG_LINK="$LOG_DIR/current_build.log"

# 计算执行时间的函数
calculate_time() {
    local end_time=$(date +%s)
    local time_taken=$((end_time - START_TIME))
    local hours=$((time_taken / 3600))
    local minutes=$(( (time_taken % 3600) / 60 ))
    local seconds=$((time_taken % 60))
    echo "总执行时间: ${hours}小时 ${minutes}分钟 ${seconds}秒"
}

# 初始化日志目录和文件
init_logging() {
    # 确保日志目录存在并有正确的权限
    sudo mkdir -p "$LOG_DIR"
    sudo chmod 755 "$LOG_DIR"
    sudo chown $(whoami):$(whoami) "$LOG_DIR"
    
    touch "$LOG_FILE"
    touch "$SUMMARY_LOG"
    
    # 更新软链接指向最新的日志文件
    ln -sf "$LOG_FILE" "$CURRENT_LOG_LINK"
    ln -sf "$SUMMARY_LOG" "$CURRENT_SUMMARY_LINK"
    
    # 同时将日志输出到文件和终端
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

# 记录重要信息到摘要日志
log_summary() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$SUMMARY_LOG"
    # 确保消息能立即写入文件
    sync
}

# 清理旧日志文件
cleanup_old_logs() {
    # 确保日志目录存在
    if [ ! -d "$LOG_DIR" ]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
        sudo chown $(whoami):$(whoami) "$LOG_DIR"
        log_summary "创建日志目录: $LOG_DIR"
        return 0
    fi
    
    # 保留最近7天的日志
    find "$LOG_DIR" -name "build_*.log" -mtime +7 -delete 2>/dev/null || true
    find "$LOG_DIR" -name "build_summary_*.log" -mtime +7 -delete 2>/dev/null || true
    log_summary "清理7天前的日志文件"
}

# 1. 更新代码
update_code() {
    log_summary "开始更新代码..."
    echo "当前更新的目录: $CORE_DIR"
    cd "$CORE_DIR" && git pull
    echo "当前更新的目录: $SDKJS_DIR"
    cd "$SDKJS_DIR" && git pull
    echo "当前更新的目录: $WEB_APPS_DIR"
    cd "$WEB_APPS_DIR" && git pull
    echo "当前更新的目录: $GITHUB_IO_DIR"
    cd "$GITHUB_IO_DIR" && git pull
    cd "$ONLYOFFICE_ROOT"
    log_summary "代码更新完成"
}

# 2. 设置版本信息
setup_version() {
    log_summary "开始设置版本信息..."
    
    # 检查是否通过环境变量传入版本信息
    if [ -n "$BUILD_VERSION" ] && [ -n "$BUILD_NUMBER" ]; then
        log_summary "使用 Jenkins 传入的版本信息:"
        log_summary "BUILD_VERSION: $BUILD_VERSION"
        log_summary "BUILD_NUMBER: $BUILD_NUMBER"
        PRODUCT_VERSION=$BUILD_VERSION
    else
        log_summary "使用本地版本信息:"
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
        
        log_summary "本地 BUILD_VERSION: $BUILD_VERSION"
        log_summary "本地 BUILD_NUMBER: $BUILD_NUMBER"
    fi
}

# 3. 编译服务
compile_service() {
    log_summary "开始编译服务..."
    local start_time=$(date +%s)
    
    # 添加参数判断是否为debug模式
    if [ "$1" = "debug" ]; then
        log_summary "使用debug模式编译..."
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
    log_summary "编译服务完成，耗时: $time_taken 秒"
}

# 4. 处理编译后的文件
post_compile() {
    log_summary "开始处理编译后的文件..."
    local api_dir="$BUILD_TOOLS_DIR/out/linux_64/onlyoffice/documentserver/web-apps/apps/api/documents"
    cd "$api_dir"
    cp api.js.tpl api.js
    cd "$ONLYOFFICE_ROOT"
    log_summary "编译后文件处理完成"
}

# 5. 打包 deb 包
build_deb() {
    log_summary "开始打包 deb 包..."
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
    log_summary "deb 包打包完成，耗时: $time_taken 秒"
}

# 6. 构建 Docker 镜像
build_docker_image() {
    log_summary "开始构建 Docker 镜像..."
    local start_time=$(date +%s)
    
    cd "$DOCKER_SERVER_DIR"
    cp "$DOC_SERVER_PACKAGE_DIR/deb/"*.deb ./
    
    DOCKER_TAG=$BUILD_VERSION-$BUILD_NUMBER
    log_summary "构建镜像标签: $DOCKER_TAG"
    
    # 构建新镜像
    docker build . -t $REGISTRY_IMAGE:$DOCKER_TAG \
        --build-arg PACKAGE_VERSION=$BUILD_VERSION-$BUILD_NUMBER
        
    # 删除旧的latest标签镜像
    docker rmi $REGISTRY_IMAGE:latest || true
    docker rmi $REGISTRY_URL:latest || true
    docker rmi $REGISTRY2_URL:latest || true
    
    # 标记新镜像
    docker tag $REGISTRY_IMAGE:$DOCKER_TAG $REGISTRY_IMAGE:latest
    
    # 删除旧版本镜像（保留最新的3个版本）
    for registry in "$REGISTRY_IMAGE" "$REGISTRY_URL" "$REGISTRY2_URL"; do
        old_tags=$(docker images "$registry" --format "{{.Tag}}" | grep -v "latest" | sort -V | head -n -3)
        for tag in $old_tags; do
            docker rmi "$registry:$tag" || true
        done
    done
    
    # 标记镜像并推送到私有仓库
    docker tag $REGISTRY_IMAGE $REGISTRY_URL
    docker tag $REGISTRY_IMAGE:$DOCKER_TAG $REGISTRY_URL:$DOCKER_TAG
    docker tag $REGISTRY_IMAGE $REGISTRY2_URL
    docker tag $REGISTRY_IMAGE:$DOCKER_TAG $REGISTRY2_URL:$DOCKER_TAG
    
    local end_time=$(date +%s)
    local time_taken=$((end_time - start_time))
    log_summary "Docker 镜像构建完成，耗时: $time_taken 秒"
}

# 7. 启动注册表服务并推送镜像
push_to_registry() {
    log_summary "开始启动本地演示服务并推送镜像到私有仓库..."
    local start_time=$(date +%s)
    
    cd "$EXAMPLE_DIR"
    docker-compose --project-directory "$EXAMPLE_DIR" up -d
    log_summary "启动 docker-compose 服务"
    
    sleep 10
    docker exec onlyoffice sudo supervisorctl start ds:example
    log_summary "启动 onlyoffice 服务"
    
    sleep 10
    
    # 临时禁用错误退出
    set +e
    
    # 推送镜像
    if ! docker push $REGISTRY_URL:latest; then
        log_summary "警告: 推送镜像 $REGISTRY_URL:latest 失败，请稍后手动推送"
    else
        log_summary "成功推送镜像 $REGISTRY_URL:latest"
    fi

    if ! docker push $REGISTRY_URL:$DOCKER_TAG; then
        log_summary "警告: 推送镜像 $REGISTRY_URL:$DOCKER_TAG 失败，请稍后手动推送"
    else
        log_summary "成功推送镜像 $REGISTRY_URL:$DOCKER_TAG"
    fi
    
    # 重新启用错误退出
    set -e
    
    local end_time=$(date +%s)
    local time_taken=$((end_time - start_time))
    log_summary "镜像推送流程完成，耗时: $time_taken 秒"
}

# 主流程
main() {
    cleanup_old_logs
    init_logging
    
    log_summary "==============================================="
    log_summary "开始 ONLYOFFICE 编译打包流程..."
    log_summary "构建机器: $(hostname)"
    log_summary "构建用户: $(whoami)"
    log_summary "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 检查命令行参数
    BUILD_TYPE="release"
    while [[ $# -gt 0 ]]; do
        case $1 in
            debug)
                BUILD_TYPE="debug"
                log_summary "使用debug模式编译"
                ;;
            --build-version=*)
                BUILD_VERSION="${1#*=}"
                export BUILD_VERSION
                ;;
            --build-number=*)
                BUILD_NUMBER="${1#*=}"
                export BUILD_NUMBER
                ;;
            *)
                log_summary "未知参数: $1"
                exit 1
                ;;
        esac
        shift
    done
    
    log_summary "构建类型: $BUILD_TYPE"
    
    update_code
    setup_version
    compile_service $BUILD_TYPE
    post_compile
    build_deb
    build_docker_image
    push_to_registry
    
    log_summary "==============================================="
    log_summary "ONLYOFFICE 编译打包流程完成！"
    log_summary "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    calculate_time | tee -a "$SUMMARY_LOG"
}

# 执行主流程
main "$@" 