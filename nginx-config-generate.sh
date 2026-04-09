#!/bin/bash
# ============================================================
#  Nginx Docker Compose 一键部署脚本（模块化版本）
#  用法: chmod +x nginx-config-generate.sh && ./nginx-config-generate.sh
# ============================================================

set -e

# ==================== 全局配置 ====================

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

PROJECT_DIR=""
CONTAINER_NAME=""
NGINX_IMAGE=""
HOST_PORT=""
HOST_SSL_PORT=""
NEED_PROXY=""
NEED_WS=""
TIMEZONE=""
PULL_IMAGE=""
NETWORK_MODE=""
NETWORK_NAME="nginx-net"

# 反向代理配置
PROXY_SERVER_NAME=""
PROXY_SCHEME=""

# WebSocket 配置
WS_SERVER_NAME=""
WS_SCHEME=""

# ==================== 日志工具 ====================

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERR ]${NC} $1"; }

print_separator() {
    echo "  ─────────────────────────────"
}

print_banner() {
    echo ""
    echo "========================================"
    echo "   Nginx Docker Compose 一键部署脚本"
    echo "========================================"
    echo ""
}

print_summary() {
    echo ""
    echo "========================================"
    echo -e "  ${GREEN}全部文件生成完毕！${NC}"
    echo "========================================"
    echo ""
    echo "  项目目录:   ./${PROJECT_DIR}"
    echo "  容器名称:   ${CONTAINER_NAME}"
    echo "  Nginx 镜像: ${NGINX_IMAGE}"
    echo "  网络模式:   ${NETWORK_MODE}"
    if [[ "${NETWORK_MODE}" != "host" && "${NETWORK_MODE}" != "none" ]]; then
        echo "  网络名称:   ${NETWORK_NAME}"
    fi
    echo "  HTTP 端口:  ${HOST_PORT}"
    echo "  HTTPS 端口: ${HOST_SSL_PORT}"
    if [[ "${NEED_PROXY,,}" == "y" ]]; then
        echo "  反向代理:   ${PROXY_SCHEME}://${PROXY_SERVER_NAME}"
    fi
    if [[ "${NEED_WS,,}" == "y" ]]; then
        echo "  WebSocket:  ${WS_SCHEME}://${WS_SERVER_NAME}"
    fi
    echo ""
}

# ==================== 用户输入 ====================

input_nginx_image() {
    echo ""
    echo "  Nginx 镜像版本选择:"
    print_separator
    echo "  [1] nginx:latest          (最新版，默认)"
    echo "  [2] nginx:stable          (稳定版)"
    echo "  [3] nginx:mainline        (主线版)"
    echo "  [4] nginx:alpine          (最新 Alpine 版)"
    echo "  [5] nginx:stable-alpine   (稳定 Alpine 版)"
    echo "  [6] nginx:mainline-alpine (主线 Alpine 版)"
    echo "  [7] 自定义版本"
    print_separator
    echo ""

    read -p "请选择镜像版本 [1]: " choice
    choice=${choice:-1}

    case ${choice} in
        1) NGINX_IMAGE="nginx:latest" ;;
        2) NGINX_IMAGE="nginx:stable" ;;
        3) NGINX_IMAGE="nginx:mainline" ;;
        4) NGINX_IMAGE="nginx:alpine" ;;
        5) NGINX_IMAGE="nginx:stable-alpine" ;;
        6) NGINX_IMAGE="nginx:mainline-alpine" ;;
        7)
            read -p "请输入自定义镜像 (如 nginx:1.27-alpine): " custom
            NGINX_IMAGE=${custom:-nginx:latest}
            ;;
        *)
            log_warn "无效选择，使用默认版本 nginx:latest"
            NGINX_IMAGE="nginx:latest"
            ;;
    esac

    log_ok "已选择镜像: ${NGINX_IMAGE}"
}

input_network_mode() {
    echo ""
    echo "  网络模式选择:"
    print_separator
    echo "  [1] bridge    (默认桥接网络，隔离安全，默认)"
    echo "  [2] host      (共享宿主机网络，性能最佳)"
    echo "  [3] none      (无网络，完全隔离)"
    echo "  [4] custom    (自定义网络，便于容器间通信)"
    print_separator
    echo ""

    read -p "请选择网络模式 [1]: " net_choice
    net_choice=${net_choice:-1}

    case ${net_choice} in
        1)
            NETWORK_MODE="bridge"
            input_network_name "bridge"
            ;;
        2)
            NETWORK_MODE="host"
            log_warn "host 模式下端口映射将失效，服务直接使用宿主机端口"
            log_warn "docker-compose.yml 中的 ports 配置将被忽略"
            ;;
        3)
            NETWORK_MODE="none"
            log_warn "none 模式下容器完全无网络，无法访问外部服务"
            ;;
        4)
            NETWORK_MODE="custom"
            input_network_name "custom"
            ;;
        *)
            log_warn "无效选择，使用默认 bridge 模式"
            NETWORK_MODE="bridge"
            input_network_name "bridge"
            ;;
    esac
}

input_network_name() {
    local mode="$1"

    echo ""
    echo "  ${mode} 模式 - 自定义网络名称:"
    print_separator
    echo "  - 只能包含字母、数字、横线、下划线"
    echo "  - 同一 Docker 环境中网络名称需唯一"
    print_separator
    echo ""

    while true; do
        read -p "请输入网络名称 [nginx-net]: " NETWORK_NAME
        NETWORK_NAME=${NETWORK_NAME:-nginx-net}

        if echo "${NETWORK_NAME}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
            break
        else
            log_warn "网络名称格式不合法，只能包含字母、数字、横线、下划线"
            continue
        fi
    done

    log_ok "已设置网络名称: ${NETWORK_NAME}"
}

input_project_config() {
    read -p "请输入容器名称 [nginx]: " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-nginx}

    read -p "请输入项目目录名称 [nginx-docker]: " PROJECT_DIR
    PROJECT_DIR=${PROJECT_DIR:-nginx-docker}

    read -p "请输入监听端口 [80]: " HOST_PORT
    HOST_PORT=${HOST_PORT:-80}

    read -p "请输入 HTTPS 端口 [443]: " HOST_SSL_PORT
    HOST_SSL_PORT=${HOST_SSL_PORT:-443}

    read -p "请输入时区 [Asia/Shanghai]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-Asia/Shanghai}
}

input_optional_features() {
    read -p "是否需要反向代理示例? (y/N): " NEED_PROXY
    NEED_PROXY=${NEED_PROXY:-n}

    read -p "是否需要 WebSocket 代理示例? (y/N): " NEED_WS
    NEED_WS=${NEED_WS:-n}
}

input_scheme() {
    local label="$1"
    local result_var="$2"

    echo ""
    echo "  ${label} - 选择协议类型:"
    print_separator
    echo "  [1] HTTP          (仅 http)"
    echo "  [2] HTTPS         (仅 https)"
    echo "  [3] HTTP + HTTPS  (同时支持，默认)"
    print_separator
    echo ""

    read -p "请选择协议 [3]: " scheme_choice
    scheme_choice=${scheme_choice:-3}

    local scheme
    case ${scheme_choice} in
        1) scheme="http" ;;
        2) scheme="https" ;;
        3) scheme="both" ;;
        *)
            log_warn "无效选择，使用默认 HTTP + HTTPS"
            scheme="both"
            ;;
    esac

    eval "${result_var}='${scheme}'"
    log_ok "已选择协议: ${scheme}"
}

input_domain() {
    local label="$1"
    local result_var="$2"

    echo ""
    echo "  ${label} - Server Name 配置:"
    print_separator
    echo "  - 支持多个域名，用空格分隔"
    echo "  - 示例: www.example.com example.com"
    echo "  - 示例: *.example.com (泛域名)"
    echo "  - 纯 IP 也可以: 192.168.1.100"
    print_separator
    echo ""

    while true; do
        read -p "请输入域名/IP (如 www.example.com): " domain

        if [[ -z "${domain}" ]]; then
            log_warn "server_name 不能为空，请输入域名或 IP"
            continue
        fi

        if echo "${domain}" | grep -qE '^[a-zA-Z0-9._* -]+$'; then
            break
        else
            log_warn "输入格式不合法，请检查是否包含特殊字符"
            continue
        fi
    done

    eval "${result_var}='${domain}'"
    log_ok "已设置 server_name: ${domain}"
}

input_proxy_config() {
    if [[ "${NEED_PROXY,,}" == "y" ]]; then
        echo ""
        echo "  ====== 反向代理配置 ======"
        input_scheme "反向代理" "PROXY_SCHEME"
        input_domain "反向代理" "PROXY_SERVER_NAME"
    fi
}

input_ws_config() {
    if [[ "${NEED_WS,,}" == "y" ]]; then
        echo ""
        echo "  ====== WebSocket 配置 ======"
        input_scheme "WebSocket" "WS_SCHEME"
        input_domain "WebSocket" "WS_SERVER_NAME"
    fi
}

input_pull_policy() {
    echo ""
    read -p "启动前是否拉取最新镜像? (Y/n): " PULL_IMAGE
    PULL_IMAGE=${PULL_IMAGE:-y}

    if [[ "${PULL_IMAGE,,}" == "y" ]]; then
        log_ok "将在启动前拉取镜像: ${NGINX_IMAGE}"
    else
        log_info "跳过镜像拉取，将使用本地已有镜像（如不存在则自动拉取）"
    fi
}

collect_all_inputs() {
    print_banner
    input_nginx_image
    input_network_mode
    input_project_config
    input_optional_features
    input_proxy_config
    input_ws_config
    input_pull_policy
    echo ""
}

# ==================== 目录创建 ====================

create_directory_structure() {
    log_info "创建目录结构..."

    mkdir -p "${PROJECT_DIR}"/nginx/{conf.d,ssl,html}
    mkdir -p "${PROJECT_DIR}"/logs/nginx

    log_ok "目录结构创建完成"
}

# ==================== 配置文件生成 ====================

generate_docker_compose() {
    log_info "生成 docker-compose.yml..."

    # 从 services 块开始构建
    local content=""
    content+="version: '3.8'"
    content+=$'\n\n'
    content+="services:"
    content+=$'\n'
    content+="  nginx:"
    content+=$'\n'
    content+="    image: ${NGINX_IMAGE}"
    content+=$'\n'
    content+="    container_name: ${CONTAINER_NAME}"
    content+=$'\n'
    content+="    restart: unless-stopped"
    content+=$'\n'

    # ports（host/none 模式不生成）
    if [[ "${NETWORK_MODE}" == "bridge" || "${NETWORK_MODE}" == "custom" ]]; then
        content+="    ports:"
        content+=$'\n'
        content+="      - \"${HOST_PORT}:80\""
        content+=$'\n'
        content+="      - \"${HOST_SSL_PORT}:443\""
        content+=$'\n'
    fi

    # volumes
    content+="    volumes:"
    content+=$'\n'
    content+="      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
    content+=$'\n'
    content+="      - ./nginx/conf.d:/etc/nginx/conf.d:ro"
    content+=$'\n'
    content+="      - ./nginx/html:/usr/share/nginx/html:ro"
    content+=$'\n'
    content+="      - ./nginx/ssl:/etc/nginx/ssl:ro"
    content+=$'\n'
    content+="      - ./logs/nginx:/var/log/nginx"
    content+=$'\n'

    # network
    case ${NETWORK_MODE} in
        bridge|custom)
            content+="    networks:"
            content+=$'\n'
            content+="      - ${NETWORK_NAME}"
            content+=$'\n'
            ;;
        host)
            content+="    network_mode: host"
            content+=$'\n'
            ;;
        none)
            content+="    network_mode: none"
            content+=$'\n'
            ;;
    esac

    # environment
    content+="    environment:"
    content+=$'\n'
    content+="      - TZ=${TIMEZONE}"

    # networks 定义（仅 bridge/custom 模式）
    if [[ "${NETWORK_MODE}" == "bridge" || "${NETWORK_MODE}" == "custom" ]]; then
        content+=$'\n\n'
        content+="networks:"
        content+=$'\n'
        content+="  ${NETWORK_NAME}:"
        content+=$'\n'
        content+="    driver: bridge"
    fi

    content+=$'\n'

    echo "${content}" > "${PROJECT_DIR}/docker-compose.yml"

    log_ok "docker-compose.yml 已生成 (网络: ${NETWORK_MODE}${NETWORK_NAME:+/${NETWORK_NAME}})"
}

generate_nginx_conf() {
    log_info "生成 nginx/nginx.conf..."

    cat > "${PROJECT_DIR}/nginx/nginx.conf" << 'NGINX_MAIN_EOF'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    keepalive_timeout  65;

    # Gzip 压缩
    gzip  on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json
               application/javascript application/xml+rss
               application/atom+xml image/svg+xml;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    include /etc/nginx/conf.d/*.conf;
}
NGINX_MAIN_EOF

    log_ok "nginx.conf 已生成"
}

generate_default_conf() {
    log_info "生成 nginx/conf.d/default.conf..."

    cat > "${PROJECT_DIR}/nginx/conf.d/default.conf" << 'DEFAULT_EOF'
server {
    listen       80;
    server_name  localhost;

    root   /usr/share/nginx/html;
    index  index.html index.htm;

    access_log  /var/log/nginx/access.log  main;
    error_log   /var/log/nginx/error.log   warn;

    location / {
        try_files $uri $uri/ =404;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny  all;
        access_log off;
        log_not_found off;
    }

    # 静态资源缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2?|ttf|svg|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # 健康检查端点
    location = /health {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
DEFAULT_EOF

    log_ok "default.conf 已生成 (server_name: localhost)"
}

generate_reverse_proxy_conf() {
    log_info "生成反向代理示例配置..."

    local scheme="${PROXY_SCHEME}"
    local server_name="${PROXY_SERVER_NAME}"

    local ssl_listen=""
    local ssl_block=""
    local redirect_block=""

    if [[ "${scheme}" == "https" || "${scheme}" == "both" ]]; then
        ssl_listen="    listen       443 ssl;
    server_name  ${server_name};"

        ssl_block="
    ssl_certificate      /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key  /etc/nginx/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;"
    fi

    if [[ "${scheme}" == "both" ]]; then
        redirect_block="
# HTTP -> HTTPS 重定向
server {
    listen 80;
    server_name ${server_name};
    return 301 https://\$host\$request_uri;
}"
    fi

    local http_listen=""
    if [[ "${scheme}" == "http" ]]; then
        http_listen="    listen       80;
    server_name  ${server_name};"
    fi

    cat > "${PROJECT_DIR}/nginx/conf.d/reverse-proxy.conf.example" << PROXY_EOF
# 使用时将此文件重命名为 .conf 后缀
# 反向代理示例 - 协议: ${scheme}

upstream backend {
    server backend-app:3000;
    keepalive 32;
}

server {
${http_listen}${ssl_listen}
${ssl_block}

    client_max_body_size 50m;

    location /api/ {
        proxy_pass http://backend;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }

    location /static/ {
        alias /usr/share/nginx/html/static/;
        expires 30d;
    }
}${redirect_block}
PROXY_EOF

    log_ok "反向代理示例已生成 (server_name: ${server_name}, scheme: ${scheme})"
}

generate_websocket_conf() {
    log_info "生成 WebSocket 代理示例配置..."

    local scheme="${WS_SCHEME}"
    local server_name="${WS_SERVER_NAME}"

    local ssl_listen=""
    local ssl_block=""
    local redirect_block=""

    if [[ "${scheme}" == "https" || "${scheme}" == "both" ]]; then
        ssl_listen="    listen       443 ssl;
    server_name  ${server_name};"

        ssl_block="
    ssl_certificate      /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key  /etc/nginx/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;"
    fi

    if [[ "${scheme}" == "both" ]]; then
        redirect_block="
# HTTP -> HTTPS 重定向
server {
    listen 80;
    server_name ${server_name};
    return 301 https://\$host\$request_uri;
}"
    fi

    local http_listen=""
    if [[ "${scheme}" == "http" ]]; then
        http_listen="    listen       80;
    server_name  ${server_name};"
    fi

    cat > "${PROJECT_DIR}/nginx/conf.d/websocket.conf.example" << WS_EOF
# 使用时将此文件重命名为 .conf 后缀
# WebSocket 代理示例 - 协议: ${scheme}

upstream ws_backend {
    server ws-app:8080;
}

server {
${http_listen}${ssl_listen}
${ssl_block}

    location /ws {
        proxy_pass http://ws_backend;

        # WebSocket 必需的三个头
        proxy_http_version 1.1;
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host            \$host;
        proxy_set_header X-Real-IP       \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        # WebSocket 长连接超时
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}${redirect_block}
WS_EOF

    log_ok "WebSocket 代理示例已生成 (server_name: ${server_name}, scheme: ${scheme})"
}

generate_ssl_readme() {
    log_info "生成 SSL 证书说明..."

    cat > "${PROJECT_DIR}/nginx/ssl/README.txt" << 'SSL_README'
如需启用 HTTPS，请将 SSL 证书文件放到此目录:
  - fullchain.pem  (证书链)
  - privkey.pem    (私钥)

可使用 Let's Encrypt 获取免费证书:
  certbot certonly --standalone -d your-domain.com

注意: 生成的 .conf.example 文件中已包含 SSL 相关配置，
      放入证书后重命名为 .conf 即可生效。
SSL_README

    log_ok "SSL 证书说明已生成"
}

generate_index_html() {
    log_info "生成测试页面 nginx/html/index.html..."

    cat > "${PROJECT_DIR}/nginx/html/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nginx 运行成功</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            color: #fff;
        }
        .card {
            text-align: center;
            padding: 3rem 4rem;
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 16px;
            backdrop-filter: blur(10px);
            max-width: 500px;
        }
        .icon { font-size: 3rem; margin-bottom: 1rem; }
        h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
        p  { color: #aaa; line-height: 1.6; }
        .time {
            margin-top: 1.5rem;
            padding: 0.8rem;
            background: rgba(255,255,255,0.08);
            border-radius: 8px;
            font-family: monospace;
            font-size: 0.9rem;
            color: #7fdbca;
        }
        .version {
            margin-top: 1rem;
            font-size: 0.8rem;
            color: #888;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">🐳</div>
        <h1>Nginx 部署成功</h1>
        <p>Docker Compose 已正常运行，Nginx 已就绪。</p>
        <div class="time" id="clock"></div>
        <div class="version" id="nginx-version"></div>
    </div>
    <script>
        function tick() {
            document.getElementById('clock').textContent =
                new Date().toLocaleString('zh-CN', { hour12: false });
        }
        tick();
        setInterval(tick, 1000);
        fetch('/health')
            .then(function() {
                document.getElementById('nginx-version').textContent = 'Nginx Server Running';
            })
            .catch(function() {});
    </script>
</body>
</html>
HTML_EOF

    log_ok "测试页面已生成"
}

generate_env_file() {
    log_info "生成 .env 文件..."

    cat > "${PROJECT_DIR}/.env" << ENV_EOF
# Nginx Docker 环境变量
NGINX_IMAGE=${NGINX_IMAGE}
CONTAINER_NAME=${CONTAINER_NAME}
NETWORK_MODE=${NETWORK_MODE}
NETWORK_NAME=${NETWORK_NAME}
NGINX_HTTP_PORT=${HOST_PORT}
NGINX_HTTPS_PORT=${HOST_SSL_PORT}
TZ=${TIMEZONE}
ENV_EOF

    log_ok ".env 文件已生成"
}

generate_gitignore() {
    log_info "生成 .gitignore..."

    cat > "${PROJECT_DIR}/.gitignore" << 'GIT_EOF'
logs/
nginx/ssl/*.pem
nginx/ssl/*.key
.env
GIT_EOF

    log_ok ".gitignore 已生成"
}

# ==================== 主生成流程 ====================

generate_all_configs() {
    generate_docker_compose
    generate_nginx_conf
    generate_default_conf
    generate_index_html
    generate_env_file
    generate_gitignore

    local has_ssl=false
    [[ "${NEED_PROXY,,}" == "y" ]] && generate_reverse_proxy_conf && [[ "${PROXY_SCHEME}" != "http" ]] && has_ssl=true
    [[ "${NEED_WS,,}"    == "y" ]] && generate_websocket_conf     && [[ "${WS_SCHEME}"    != "http" ]] && has_ssl=true

    [[ "${has_ssl}" == "true" ]] && generate_ssl_readme
}

# ==================== 文件清单 ====================

show_file_tree() {
    log_info "文件结构:"
    find "${PROJECT_DIR}" -type f | sort | sed "s|^|  |"
    echo ""
}

# ==================== 镜像拉取 ====================

pull_docker_image() {
    if [[ "${PULL_IMAGE,,}" == "y" ]]; then
        log_info "正在拉取镜像 ${NGINX_IMAGE} ..."
        echo ""

        if docker pull "${NGINX_IMAGE}"; then
            echo ""
            log_ok "镜像拉取成功"
            local image_info
            image_info=$(docker images "${NGINX_IMAGE}" --format "{{.Repository}}:{{.Tag}}  {{.Size}}  {{.CreatedAt}}" | head -1)
            log_info "镜像信息: ${image_info}"
        else
            echo ""
            log_error "镜像拉取失败，请检查网络或镜像名称是否正确"
            log_warn "跳过拉取，启动时 Docker 会自动尝试拉取"
        fi
        echo ""
    else
        log_info "跳过镜像拉取步骤"
    fi
}

# ==================== 服务启动 ====================

start_service() {
    read -p "是否立即启动服务? (Y/n): " answer
    answer=${answer:-y}

    if [[ "${answer,,}" == "y" ]]; then
        log_info "启动 Docker Compose 服务..."
        cd "${PROJECT_DIR}"
        docker-compose up -d

        echo ""

        if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            log_ok "容器 ${CONTAINER_NAME} 已成功启动"
        else
            log_warn "容器可能未正常启动，请检查日志"
        fi

        echo ""
        echo "  访问地址: http://localhost:${HOST_PORT}"
        echo ""
        echo "  常用命令:"
        echo "    查看状态:  cd ${PROJECT_DIR} && docker-compose ps"
        echo "    查看日志:  cd ${PROJECT_DIR} && docker-compose logs -f"
        echo "    重启服务:  cd ${PROJECT_DIR} && docker-compose restart"
        echo "    停止服务:  cd ${PROJECT_DIR} && docker-compose down"
        echo "    删除容器:  cd ${PROJECT_DIR} && docker-compose down -v"
        echo ""
    fi
}

# ==================== 主入口 ====================

main() {
    collect_all_inputs
    create_directory_structure
    generate_all_configs
    print_summary
    show_file_tree
    pull_docker_image
    start_service
    log_ok "完成！"
}

main "$@"
