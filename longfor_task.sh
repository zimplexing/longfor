#!/bin/bash
# 龙湖天街自动化任务脚本 - 纯bash版本
# 功能：1.每日签到 2.抽奖系统 4.账户查询

set -eo pipefail

# 基础URL
BASE_URL="https://gw2c-hw-open.longfor.com"
LONGZHU_API_URL="https://longzhu-api.longfor.com"

# 日志函数
log_info() {
    echo -e "[INFO] $1"
}

log_success() {
    echo -e "[SUCCESS] $1"
}

log_warning() {
    echo -e "[WARNING] $1"
}

log_error() {
    echo -e "[ERROR] $1"
}

# 随机延迟函数
random_sleep() {
    local min=$1
    local max=$2
    # 简化版，使用整数睡眠
    local sleep_range=$((max - min))
    local sleep_time=$((min + RANDOM % (sleep_range + 1)))
    log_info "等待 $sleep_time 秒..."
    sleep "$sleep_time"
}

# 随机选择User-Agent
get_random_user_agent() {
    local user_agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0"
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1"
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    )
    echo "${user_agents[$RANDOM % ${#user_agents[@]}]}"
}

# 构建请求头
build_headers() {
    local headers=()

    # 基础headers
    headers+=("-H" "Host: gw2c-hw-open.longfor.com")
    headers+=("-H" "Connection: keep-alive")
    headers+=("-H" "xweb_xhr: 1")
    headers+=("-H" "X-LF-Bucode: ${X_LF_BUCODE:-C20400}")
    headers+=("-H" "X-LF-Api-Version: ${X_LF_API_VERSION:-v1_23_2}")
    headers+=("-H" "X-LF-Channel: ${X_LF_CHANNEL:-C2}")
    headers+=("-H" "X-Client-Type: ${X_CLIENT_TYPE:-microApp}")
    headers+=("-H" "Content-Type: application/json")
    headers+=("-H" "User-Agent: ${USER_AGENT:-$(get_random_user_agent)}")
    headers+=("-H" "Accept: */*")
    headers+=("-H" "Sec-Fetch-Site: cross-site")
    headers+=("-H" "Sec-Fetch-Mode: cors")
    headers+=("-H" "Sec-Fetch-Dest: empty")
    headers+=("-H" "Referer: ${REFERER:-https://servicewechat.com/wx50282644351869da/493/page-frame.html}")
    headers+=("-H" "Accept-Encoding: gzip, deflate, br")
    headers+=("-H" "Accept-Language: zh-CN,zh;q=0.9")

    # 可选但重要的headers
    if [ -n "$X_LONGZHU_SIGN" ]; then
        headers+=("-H" "X-LONGZHU-Sign: $X_LONGZHU_SIGN")
    fi

    if [ -n "$LM_TOKEN" ]; then
        headers+=("-H" "lmToken: $LM_TOKEN")
    fi

    if [ -n "$X_GAIA_API_KEY" ]; then
        headers+=("-H" "X-Gaia-Api-Key: $X_GAIA_API_KEY")
    fi

    echo "${headers[@]}"
}

# 发送POST请求
post_request() {
    local url="$1"
    local data="$2"
    local headers=($(build_headers))

    log_info "发送POST请求到: $url"
    log_info "请求数据: $data"

    response=$(curl -s -w "\n%{http_code}" -X POST "${headers[@]}" -d "$data" "$url" 2>/dev/null)

    log_info "响应内容: $response"

    echo "$response"
}

# 发送GET请求
get_request() {
    local url="$1"
    local params="$2"
    local headers=($(build_headers))

    if [ -n "$params" ]; then
        url="$url?$params"
    fi

    log_info "发送GET请求到: $url"

    response=$(curl -s -w "\n%{http_code}" -X GET "${headers[@]}" "$url" 2>/dev/null)

    log_info "响应内容: $response"

    echo "$response"
}

# 提取JSON中的字段值（使用grep和sed，不依赖jq）
extract_json_field() {
    local json="$1"
    local field="$2"

    # 方法1：提取带双引号的字符串字段
    local result=$(echo "$json" | grep -o "\"$field\":\"[^\"]*\"" | sed "s/\"$field\":\"//;s/\"$//" | head -1)
    if [ -n "$result" ]; then
        echo "$result"
        return
    fi

    # 方法2：尝试不带外层引号
    result=$(echo "$json" | grep -o "$field\":\"[^\"]*\"" | sed "s/$field\":\"//;s/\"$//" | head -1)
    if [ -n "$result" ]; then
        echo "$result"
        return
    fi

    echo ""
}

extract_json_number() {
    local json="$1"
    local field="$2"

    # 方法1：提取数字字段（支持小数）
    local result=$(echo "$json" | grep -o "\"$field\":[0-9]*\.[0-9]*\|\"$field\":[0-9]*" | sed "s/\"$field\"://" | head -1)
    if [ -n "$result" ]; then
        echo "$result"
        return
    fi

    # 方法2：尝试不带外层引号
    result=$(echo "$json" | grep -o "$field\":[0-9]*\.[0-9]*\|$field\":[0-9]*" | sed "s/$field\"://" | head -1)
    if [ -n "$result" ]; then
        echo "$result"
        return
    fi

    echo "0"
}

# 检查响应是否成功
check_response_success() {
    local response="$1"
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log_error "HTTP请求失败，状态码: $http_code"
        return 1
    fi

    # 检查是否包含错误消息
    if echo "$body" | grep -q "登录已过期\|用户未登录"; then
        log_error "登录已过期，请更新token"
        return 1
    fi

    echo "$body"
    return 0
}

# 每日签到
signin() {
    log_info "开始每日签到..."

    local url="${BASE_URL}/lmarketing-task-api-mvc-prod/openapi/task/v1/signature/clock"
    local data='{"activity_no":"11111111111686241863606037740000"}'

    local response=$(post_request "$url" "$data")
    log_info "signin requested"
    local body=$(check_response_success "$response") || return 1
    log_info "signin responsed"
    
    # 检查是否签到成功
    if echo "$body" | grep -q '"is_popup":1'; then
        local reward_num=$(extract_json_number "$body" "reward_num")
        log_success "每日签到成功！获得 ${reward_num:-0} 分"
    else
        log_warning "今日已签到"
    fi
}

# 获取抽奖活动信息
get_lottery_activity_info() {
    log_info "获取抽奖活动信息..."

    local url="${BASE_URL}/llt-gateway-prod/api/v1/page/info"
    local params="activityNo=AP25Z07390KXCWDP&pageNo=PP11I27P15H4JYOY"

    local response=$(get_request "$url" "$params")
    local body=$(check_response_success "$response") || return 1

    # 提取activity_no
    local activity_no=$(extract_json_field "$body" "activity_no")

    # 提取info中的component_no
    local info_str=$(extract_json_field "$body" "info")
    if [ -z "$info_str" ]; then
        log_error "无法获取活动信息"
        return 1
    fi

    # 从info中查找turntablecom的component_no
    local component_no=$(echo "$info_str" | grep -o '"comName":"turntablecom"' -A 50 | grep -o '"component_no":"[^"]*"' | sed 's/"component_no":"//;s/"$//' | head -1)

    if [ -z "$activity_no" ] || [ -z "$component_no" ]; then
        log_error "无法提取活动ID"
        return 1
    fi

    log_success "获取活动信息成功: activity_no=$activity_no, component_no=$component_no"
    echo "$activity_no|$component_no"
}

# 抽奖签到
lottery_signin() {
    local activity_info="$1"
    local activity_no=$(echo "$activity_info" | cut -d'|' -f1)
    local component_no=$(echo "$activity_info" | cut -d'|' -f2)

    log_info "开始抽奖签到..."

    local url="${BASE_URL}/llt-gateway-prod/api/v1/activity/auth/lottery/sign"
    local data="{\"component_no\":\"$component_no\",\"activity_no\":\"$activity_no\"}"

    local response=$(post_request "$url" "$data")
    local body=$(check_response_success "$response") || return 1

    if echo "$body" | grep -q '"code":"0000"'; then
        local chance=$(extract_json_number "$body" "chance")
        log_success "抽奖签到成功！获得 ${chance:-0} 次抽奖机会"
        # 只输出数字，去除所有颜色和格式字符
        echo "$chance" | tr -dc '0-9'
    else
        local message=$(extract_json_field "$body" "message")
        log_warning "抽奖签到: ${message:-未知错误}"
        echo "0"
    fi
}

# 抽奖
lottery_clock() {
    local activity_info="$1"
    local activity_no=$(echo "$activity_info" | cut -d'|' -f1)
    local component_no=$(echo "$activity_info" | cut -d'|' -f2)

    log_info "开始抽奖..."

    local url="${BASE_URL}/llt-gateway-prod/api/v1/activity/auth/lottery/click"
    local data="{\"component_no\":\"$component_no\",\"activity_no\":\"$activity_no\",\"batch_no\":\"\"}"

    local response=$(post_request "$url" "$data")
    local body=$(check_response_success "$response") || return 1

    if echo "$body" | grep -q '"code":"0000"'; then
        local reward_type=$(extract_json_number "$body" "reward_type")
        local reward_num=$(extract_json_number "$body" "reward_num")

        if [ -n "$reward_type" ] && [ "$reward_type" != "0" ] && [ -n "$reward_num" ] && [ "$reward_num" != "0" ]; then
            log_success "抽奖成功！获得奖励类型: $reward_type, 数量: $reward_num"
        else
            log_success "抽奖完成"
        fi
    else
        local message=$(extract_json_field "$body" "message")
        log_warning "抽奖: ${message:-未知错误}"
    fi
}

# 查询用户信息
get_user_info() {
    log_info "查询用户信息..."

    local url="${LONGZHU_API_URL}/lmember-member-open-api-prod/api/member/v1/mine-info"
    local data="{\"channel\":\"${X_LF_CHANNEL:-C2}\",\"bu_code\":\"${X_LF_BUCODE:-C20400}\",\"token\":\"${LM_TOKEN:-}\"}"

    # 注意：用户信息查询需要使用特定的API key
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Host: longzhu-api.longfor.com" \
        -H "Content-Type: application/json" \
        -H "X-Gaia-Api-Key: d1eb973c-64ec-4dbe-b23b-22c8117c4e8e" \
        -H "User-Agent: ${USER_AGENT:-$(get_random_user_agent)}" \
        -H "Referer: ${REFERER:-https://servicewechat.com/wx50282644351869da/493/page-frame.html}" \
        -H "token: ${LM_TOKEN:-}" \
        -d "$data" "$url" 2>/dev/null)

    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log_error "HTTP请求失败，状态码: $http_code"
        return 1
    fi

    if [ "$DEBUG" = "true" ]; then
        log_info "用户信息查询响应: $body"
    fi

    if echo "$body" | grep -q '"code":"0000"'; then
        local nick_name=$(extract_json_field "$body" "nick_name")
        local growth_value=$(extract_json_number "$body" "growth_value")
        local level=$(extract_json_number "$body" "level")

        log_success "用户: ${nick_name:-未知用户}"
        log_success "成长值: ${growth_value:-0}, 等级: V${level:-0}"
        echo "$nick_name|$growth_value|$level"
    else
        local message=$(extract_json_field "$body" "message")
        log_error "查询用户信息: ${message:-失败}"
        return 1
    fi
}

# 查询珑珠余额
get_balance() {
    log_info "查询珑珠余额..."

    local url="${LONGZHU_API_URL}/lmember-member-open-api-prod/api/member/v1/balance"
    local data="{\"channel\":\"${X_LF_CHANNEL:-C2}\",\"bu_code\":\"${X_LF_BUCODE:-C20400}\",\"token\":\"${LM_TOKEN:-}\"}"

    # 注意：珑珠查询需要使用特定的API key
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Host: longzhu-api.longfor.com" \
        -H "Content-Type: application/json" \
        -H "X-Gaia-Api-Key: d1eb973c-64ec-4dbe-b23b-22c8117c4e8e" \
        -H "User-Agent: ${USER_AGENT:-$(get_random_user_agent)}" \
        -H "Referer: ${REFERER:-https://servicewechat.com/wx50282644351869da/493/page-frame.html}" \
        -H "token: ${LM_TOKEN:-}" \
        -d "$data" "$url" 2>/dev/null)

    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log_error "HTTP请求失败，状态码: $http_code"
        return 1
    fi

    if [ "$DEBUG" = "true" ]; then
        log_info "珑珠查询响应: $body"
    fi

    if echo "$body" | grep -q '"code":"0000"'; then
        local balance=$(extract_json_number "$body" "balance")
        local expiring_lz=$(extract_json_number "$body" "expiring_lz")

        log_success "珑珠余额: ${balance:-0}"
        log_success "即将过期: ${expiring_lz:-0}"
        echo "$balance|$expiring_lz"
    else
        local message=$(extract_json_field "$body" "message")
        log_error "查询珑珠余额: ${message:-失败}"
        return 1
    fi
}

# 检查环境变量
check_env() {
    local missing_vars=""

    if [ -z "$X_LONGZHU_SIGN" ]; then
        missing_vars="$missing_vars X_LONGZHU_SIGN"
    fi

    if [ -z "$LM_TOKEN" ]; then
        missing_vars="$missing_vars LM_TOKEN"
    fi

    if [ -n "$missing_vars" ]; then
        log_error "缺少必要的环境变量:$missing_vars"
        echo
        echo "请设置以下环境变量："
        echo "  export X_LONGZHU_SIGN=\"你的签名值\""
        echo "  export LM_TOKEN=\"你的token\""
        echo
        echo "可选环境变量："
        echo "  export X_GAIA_API_KEY=\"API key (默认: d1eb973c-64ec-4dbe-b23b-22c8117c4e8e)\""
        echo "  export USER_AGENT=\"用户代理\""
        echo "  export X_LF_BUCODE=\"业务代码 (默认: C20400)\""
        echo "  export X_LF_CHANNEL=\"渠道代码 (默认: C2)\""
        echo "  export X_LF_API_VERSION=\"API版本 (默认: v1_23_2)\""
        echo "  export X_CLIENT_TYPE=\"客户端类型 (默认: microApp)\""
        echo "  export REFERER=\"来源地址\""
        echo "  export DEBUG=\"true\"  # 启用调试模式"
        return 1
    fi

    # 设置默认值
    if [ -z "$X_GAIA_API_KEY" ]; then
        export X_GAIA_API_KEY="d1eb973c-64ec-4dbe-b23b-22c8117c4e8e"
    fi

    return 0
}

# 显示帮助
show_help() {
    cat << EOF
龙湖天街自动化任务脚本 - 纯bash版本

功能：
  1. 每日签到 - 自动完成每日签到获取积分
  2. 抽奖系统 - 自动完成抽奖签到和抽奖
  4. 账户查询 - 查询用户信息和珑珠余额

使用方法：
  $0 [选项]

选项：
  -h, --help     显示帮助信息
  -d, --debug    启用调试模式
  -s, --signin   仅执行签到
  -l, --lottery  仅执行抽奖
  -q, --query    仅执行查询

环境变量（必需）：
  X_LONGZHU_SIGN  请求签名
  LM_TOKEN        用户令牌

环境变量（可选）：
  X_GAIA_API_KEY  API密钥
  USER_AGENT      用户代理
  X_LF_BUCODE     业务代码
  X_LF_CHANNEL    渠道代码
  ...             更多选项请查看代码

示例：
  # 执行所有任务
  export X_LONGZHU_SIGN="your_sign"
  export LM_TOKEN="your_token"
  $0

  # 仅执行签到
  $0 --signin

  # 启用调试模式
  export DEBUG=true
  $0
EOF
}

# 主函数
main() {
    local mode="all"

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                export DEBUG=true
                shift
                ;;
            -s|--signin)
                mode="signin"
                shift
                ;;
            -l|--lottery)
                mode="lottery"
                shift
                ;;
            -q|--query)
                mode="query"
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "龙湖天街自动化任务 - Bash版本"
    echo "=============================================="
    echo

    # 检查环境变量
    check_env || exit 1

    case $mode in
        all)
            # 执行所有任务
            random_sleep 5 15
            signin || true

            local activity_info=$(get_lottery_activity_info)
            if [ -n "$activity_info" ]; then
                log_info "获取抽奖签到信息..."
                local chance_output=$(lottery_signin "$activity_info")
                local chance=$(echo "$chance_output" | grep -oE '[0-9]+' | head -1)

                if [ -n "$chance" ] && [ "$chance" -gt 0 ]; then
                    log_info "获得 $chance 次抽奖机会"
                    for ((i=0; i<chance; i++)); do
                        lottery_clock "$activity_info"
                        if [ $((i+1)) -lt $chance ]; then
                            random_sleep 3 5
                        fi
                    done
                else
                    log_warning "没有获得抽奖机会，跳过抽奖"
                fi
            fi

            echo
            get_user_info || true
            get_balance || true
            ;;

        signin)
            # 仅执行签到
            random_sleep 5 15
            signin
            ;;

        lottery)
            # 仅执行抽奖
            local activity_info=$(get_lottery_activity_info)
            if [ -n "$activity_info" ]; then
                log_info "获取抽奖签到信息..."
                local chance_output=$(lottery_signin "$activity_info")
                local chance=$(echo "$chance_output" | grep -oE '[0-9]+' | head -1)

                if [ -n "$chance" ] && [ "$chance" -gt 0 ]; then
                    log_info "获得 $chance 次抽奖机会"
                    for ((i=0; i<chance; i++)); do
                        lottery_clock "$activity_info"
                        if [ $((i+1)) -lt $chance ]; then
                            random_sleep 3 5
                        fi
                    done
                else
                    log_warning "没有获得抽奖机会，跳过抽奖"
                fi
            fi
            ;;

        query)
            # 仅执行查询
            get_user_info
            get_balance
            ;;
    esac

    echo
    echo "=============================================="
    log_success "任务执行完成！"
    echo "=============================================="
}

# 运行主函数
main "$@"
