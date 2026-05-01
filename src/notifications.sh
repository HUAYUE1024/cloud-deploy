#!/bin/bash
#
# Cloud Deploy - 通知函数库
# 版本: 3.0.0
#

# 加载工具函数
SCRIPT_DIR_NOTIFY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR_NOTIFY}/utils.sh" ] && source "${SCRIPT_DIR_NOTIFY}/utils.sh"

# ============================================
# 通知核心函数
# ============================================

# 发送通知（通用）
send_notification() {
    local channel=$1
    local status=$2
    local title=$3
    local content=$4
    local extra_data=${5:-""}

    case ${channel} in
        email)
            send_email_notification "${status}" "${title}" "${content}"
            ;;
        dingtalk)
            send_dingtalk_notification "${status}" "${title}" "${content}"
            ;;
        slack)
            send_slack_notification "${status}" "${title}" "${content}"
            ;;
        wechat)
            send_wechat_notification "${status}" "${title}" "${content}"
            ;;
        feishu)
            send_feishu_notification "${status}" "${title}" "${content}"
            ;;
        webhook)
            send_webhook_notification "${status}" "${title}" "${content}" "${extra_data}"
            ;;
        all)
            send_all_notifications "${status}" "${title}" "${content}"
            ;;
        *)
            log_warn "未知通知渠道: ${channel}"
            ;;
    esac
}

# 发送所有通知
send_all_notifications() {
    local status=$1
    local title=$2
    local content=$3

    # 并行发送所有通知
    send_email_notification "${status}" "${title}" "${content}" &
    send_dingtalk_notification "${status}" "${title}" "${content}" &
    send_slack_notification "${status}" "${title}" "${content}" &
    send_wechat_notification "${status}" "${title}" "${content}" &
    send_feishu_notification "${status}" "${title}" "${content}" &

    # 等待所有通知完成
    wait
}

# 获取状态图标
get_status_icon() {
    local status=$1

    case ${status} in
        success)  echo "✅" ;;
        failure)  echo "❌" ;;
        rollback) echo "⚠️" ;;
        warning)  echo "⚠️" ;;
        info)     echo "ℹ️" ;;
        *)        echo "📋" ;;
    esac
}

# 获取状态颜色
get_status_color() {
    local status=$1

    case ${status} in
        success)  echo "#4CAF50" ;;
        failure)  echo "#F44336" ;;
        rollback) echo "#FF9800" ;;
        warning)  echo "#FFC107" ;;
        info)     echo "#2196F3" ;;
        *)        echo "#9E9E9E" ;;
    esac
}

# 构建通知消息
build_notification_message() {
    local status=$1
    local title=$2
    local content=$3
    local format=${4:-"text"}  # text, markdown, html

    local icon=$(get_status_icon "${status}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(get_hostname 2>/dev/null || echo "unknown")
    local version=$(git describe --tags --always 2>/dev/null || echo "unknown")

    case ${format} in
        text)
            cat << EOF
${icon} ${title}

状态: ${status}
内容: ${content}
时间: ${timestamp}
主机: ${hostname}
版本: ${version}
EOF
            ;;
        markdown)
            cat << EOF
${icon} **${title}**

| 项目 | 值 |
|------|-----|
| 状态 | ${status} |
| 内容 | ${content} |
| 时间 | ${timestamp} |
| 主机 | ${hostname} |
| 版本 | ${version} |
EOF
            ;;
        html)
            cat << EOF
<html>
<body>
<h2>${icon} ${title}</h2>
<table>
<tr><td><b>状态</b></td><td>${status}</td></tr>
<tr><td><b>内容</b></td><td>${content}</td></tr>
<tr><td><b>时间</b></td><td>${timestamp}</td></tr>
<tr><td><b>主机</b></td><td>${hostname}</td></tr>
<tr><td><b>版本</b></td><td>${version}</td></tr>
</table>
</body>
</html>
EOF
            ;;
    esac
}

# ============================================
# 邮件通知
# ============================================

# 发送邮件通知
send_email_notification() {
    local status=$1
    local title=$2
    local content=$3

    # 检查邮件配置
    local enabled=${EMAIL_ENABLED:-false}
    if [ "${enabled}" != "true" ]; then
        return 0
    fi

    log_info "发送邮件通知..."

    local smtp_host=${EMAIL_SMTP_HOST:-""}
    local smtp_port=${EMAIL_SMTP_PORT:-"587"}
    local smtp_user=${EMAIL_SMTP_USER:-""}
    local smtp_pass=${EMAIL_SMTP_PASSWORD:-""}
    local from=${EMAIL_FROM:-""}
    local recipients=${EMAIL_RECIPIENTS:-""}

    if [ -z "${smtp_host}" ] || [ -z "${recipients}" ]; then
        log_warn "邮件配置不完整，跳过发送"
        return 0
    fi

    local icon=$(get_status_icon "${status}")
    local subject="${icon} [${status}] ${title}"
    local body=$(build_notification_message "${status}" "${title}" "${content}" "html")

    # 发送给每个收件人
    local send_count=0
    local fail_count=0

    for recipient in ${recipients//,/ }; do
        if echo "${body}" | mail -s "${subject}" \
            -S smtp="smtp://${smtp_host}:${smtp_port}" \
            -S smtp-auth=login \
            -S smtp-auth-user="${smtp_user}" \
            -S smtp-auth-password="${smtp_pass}" \
            -S from="${from}" \
            -S content-type="text/html; charset=UTF-8" \
            "${recipient}" 2>/dev/null; then
            send_count=$((send_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    log_info "邮件通知完成: 成功 ${send_count}, 失败 ${fail_count}"
}

# 发送邮件（使用 curl SMTP）
send_email_curl() {
    local smtp_host=$1
    local smtp_port=$2
    local smtp_user=$3
    local smtp_pass=$4
    local from=$5
    local to=$6
    local subject=$7
    local body=$8

    curl -s --url "smtp://${smtp_host}:${smtp_port}" \
        --ssl-reqd \
        --mail-from "${from}" \
        --mail-rcpt "${to}" \
        --user "${smtp_user}:${smtp_pass}" \
        -T - << EOF
From: ${from}
To: ${to}
Subject: ${subject}
Content-Type: text/html; charset=UTF-8

${body}
EOF
}

# ============================================
# 钉钉通知
# ============================================

# 发送钉钉通知
send_dingtalk_notification() {
    local status=$1
    local title=$2
    local content=$3

    local webhook=${DINGTALK_WEBHOOK:-""}
    if [ -z "${webhook}" ]; then
        return 0
    fi

    log_info "发送钉钉通知..."

    local icon=$(get_status_icon "${status}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local version=$(git describe --tags --always 2>/dev/null || echo "unknown")

    # 钉钉 Markdown 消息
    local markdown_content="## ${icon} ${title}\n\n"
    markdown_content+="${content}\n\n"
    markdown_content+="---\n"
    markdown_content+="- **状态**: ${status}\n"
    markdown_content+="- **时间**: ${timestamp}\n"
    markdown_content+="- **版本**: ${version}\n"

    local response=$(curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msgtype\": \"markdown\",
            \"markdown\": {
                \"title\": \"${icon} ${title}\",
                \"text\": \"${markdown_content}\"
            }
        }")

    if echo "${response}" | grep -q '"errcode":0'; then
        log_info "钉钉通知发送成功"
    else
        log_error "钉钉通知发送失败: ${response}"
    fi
}

# 发送钉钉文本消息
send_dingtalk_text() {
    local webhook=$1
    local content=$2
    local at_all=${3:-false}

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msgtype\": \"text\",
            \"text\": {
                \"content\": \"${content}\"
            },
            \"at\": {
                \"isAtAll\": ${at_all}
            }
        }"
}

# 发送钉钉 ActionCard 消息
send_dingtalk_actioncard() {
    local webhook=$1
    local title=$2
    local content=$3
    local btn_title=${4:-"查看详情"}
    local btn_url=${5:-""}

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msgtype\": \"actionCard\",
            \"actionCard\": {
                \"title\": \"${title}\",
                \"text\": \"${content}\",
                \"btnOrientation\": \"0\",
                \"singleTitle\": \"${btn_title}\",
                \"singleURL\": \"${btn_url}\"
            }
        }"
}

# ============================================
# Slack 通知
# ============================================

# 发送 Slack 通知
send_slack_notification() {
    local status=$1
    local title=$2
    local content=$3

    local webhook=${SLACK_WEBHOOK:-""}
    local channel=${SLACK_CHANNEL:-"#deployments"}

    if [ -z "${webhook}" ]; then
        return 0
    fi

    log_info "发送 Slack 通知..."

    local icon=$(get_status_icon "${status}")
    local color=$(get_status_color "${status}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local version=$(git describe --tags --always 2>/dev/null || echo "unknown")

    # Slack Block Kit 消息
    local response=$(curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"channel\": \"${channel}\",
            \"attachments\": [
                {
                    \"color\": \"${color}\",
                    \"blocks\": [
                        {
                            \"type\": \"header\",
                            \"text\": {
                                \"type\": \"plain_text\",
                                \"text\": \"${icon} ${title}\"
                            }
                        },
                        {
                            \"type\": \"section\",
                            \"text\": {
                                \"type\": \"mrkdwn\",
                                \"text\": \"${content}\"
                            }
                        },
                        {
                            \"type\": \"section\",
                            \"fields\": [
                                {
                                    \"type\": \"mrkdwn\",
                                    \"text\": \"*状态:*\\n${status}\"
                                },
                                {
                                    \"type\": \"mrkdwn\",
                                    \"text\": \"*版本:*\\n${version}\"
                                }
                            ]
                        },
                        {
                            \"type\": \"context\",
                            \"elements\": [
                                {
                                    \"type\": \"mrkdwn\",
                                    \"text\": \"${timestamp}\"
                                }
                            ]
                        }
                    ]
                }
            ]
        }")

    if [ "${response}" = "ok" ]; then
        log_info "Slack 通知发送成功"
    else
        log_error "Slack 通知发送失败: ${response}"
    fi
}

# 发送 Slack 简单消息
send_slack_simple() {
    local webhook=$1
    local text=$2
    local channel=${3:-""}

    local payload="{\"text\": \"${text}\""
    [ -n "${channel}" ] && payload="${payload}, \"channel\": \"${channel}\""
    payload="${payload}}"

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "${payload}"
}

# ============================================
# 企业微信通知
# ============================================

# 发送企业微信通知
send_wechat_notification() {
    local status=$1
    local title=$2
    local content=$3

    local webhook=${WECHAT_WEBHOOK:-""}
    if [ -z "${webhook}" ]; then
        return 0
    fi

    log_info "发送企业微信通知..."

    local icon=$(get_status_icon "${status}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 企业微信 Markdown 消息
    local markdown_content="## ${icon} ${title}\n\n"
    markdown_content+="${content}\n\n"
    markdown_content+="> 状态: ${status}\n"
    markdown_content+="> 时间: ${timestamp}\n"

    local response=$(curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msgtype\": \"markdown\",
            \"markdown\": {
                \"content\": \"${markdown_content}\"
            }
        }")

    if echo "${response}" | grep -q '"errcode":0'; then
        log_info "企业微信通知发送成功"
    else
        log_error "企业微信通知发送失败: ${response}"
    fi
}

# 发送企业微信文本消息
send_wechat_text() {
    local webhook=$1
    local content=$2
    local mentioned_list=${3:-""}

    local payload="{
        \"msgtype\": \"text\",
        \"text\": {
            \"content\": \"${content}\""

    if [ -n "${mentioned_list}" ]; then
        payload="${payload},
            \"mentioned_list\": [${mentioned_list}]"
    fi

    payload="${payload}
        }
    }"

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "${payload}"
}

# ============================================
# 飞书通知
# ============================================

# 发送飞书通知
send_feishu_notification() {
    local status=$1
    local title=$2
    local content=$3

    local webhook=${FEISHU_WEBHOOK:-""}
    if [ -z "${webhook}" ]; then
        return 0
    fi

    log_info "发送飞书通知..."

    local icon=$(get_status_icon "${status}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local version=$(git describe --tags --always 2>/dev/null || echo "unknown")

    # 飞书富文本消息
    local response=$(curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msg_type\": \"interactive\",
            \"card\": {
                \"header\": {
                    \"title\": {
                        \"tag\": \"plain_text\",
                        \"content\": \"${icon} ${title}\"
                    },
                    \"template\": \"$(get_feishu_template ${status})\"
                },
                \"elements\": [
                    {
                        \"tag\": \"div\",
                        \"text\": {
                            \"tag\": \"lark_md\",
                            \"content\": \"${content}\"
                        }
                    },
                    {
                        \"tag\": \"hr\"
                    },
                    {
                        \"tag\": \"div\",
                        \"fields\": [
                            {
                                \"is_short\": true,
                                \"text\": {
                                    \"tag\": \"lark_md\",
                                    \"content\": \"**状态:** ${status}\"
                                }
                            },
                            {
                                \"is_short\": true,
                                \"text\": {
                                    \"tag\": \"lark_md\",
                                    \"content\": \"**版本:** ${version}\"
                                }
                            }
                        ]
                    },
                    {
                        \"tag\": \"note\",
                        \"elements\": [
                            {
                                \"tag\": \"plain_text\",
                                \"content\": \"${timestamp}\"
                            }
                        ]
                    }
                ]
            }
        }")

    if echo "${response}" | grep -q '"StatusCode":0'; then
        log_info "飞书通知发送成功"
    else
        log_error "飞书通知发送失败: ${response}"
    fi
}

# 获取飞书卡片模板颜色
get_feishu_template() {
    local status=$1

    case ${status} in
        success)  echo "green" ;;
        failure)  echo "red" ;;
        rollback) echo "orange" ;;
        warning)  echo "yellow" ;;
        *)        echo "blue" ;;
    esac
}

# 发送飞书文本消息
send_feishu_text() {
    local webhook=$1
    local content=$2

    curl -s -X POST "${webhook}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"msg_type\": \"text\",
            \"content\": {
                \"text\": \"${content}\"
            }
        }"
}

# ============================================
# Webhook 通知
# ============================================

# 发送自定义 Webhook 通知
send_webhook_notification() {
    local status=$1
    local title=$2
    local content=$3
    local extra_data=${4:-""}

    local webhook_url=${WEBHOOK_URL:-""}
    if [ -z "${webhook_url}" ]; then
        return 0
    fi

    log_info "发送 Webhook 通知..."

    local icon=$(get_status_icon "${status}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local version=$(git describe --tags --always 2>/dev/null || echo "unknown")

    # 构建 JSON payload
    local payload="{
        \"status\": \"${status}\",
        \"title\": \"${title}\",
        \"content\": \"${content}\",
        \"icon\": \"${icon}\",
        \"timestamp\": \"${timestamp}\",
        \"version\": \"${version}\",
        \"hostname\": \"$(get_hostname 2>/dev/null || echo unknown)\"
    }"

    # 添加额外数据
    if [ -n "${extra_data}" ]; then
        payload=$(echo "${payload}" | sed "s/}$/${extra_data},/")
        payload="${payload}}"
    fi

    local response=$(curl -s -X POST "${webhook_url}" \
        -H 'Content-Type: application/json' \
        -d "${payload}")

    log_info "Webhook 通知已发送"
    echo "${response}"
}

# ============================================
# 通知模板
# ============================================

# 部署成功通知模板
notify_deploy_success() {
    local project=$1
    local version=$2
    local environment=$3
    local server=$4
    local duration=$5

    local content="**项目**: ${project}\n"
    content+="**版本**: ${version}\n"
    content+="**环境**: ${environment}\n"
    content+="**服务器**: ${server}\n"
    content+="**耗时**: ${duration}秒"

    send_all_notifications "success" "部署成功 - ${project}" "${content}"
}

# 部署失败通知模板
notify_deploy_failure() {
    local project=$1
    local reason=$2
    local details=${3:-""}

    local content="**项目**: ${project}\n"
    content+="**原因**: ${reason}\n"
    [ -n "${details}" ] && content+="**详情**: ${details}"

    send_all_notifications "failure" "部署失败 - ${project}" "${content}"
}

# 回滚通知模板
notify_rollback() {
    local project=$1
    local from_version=$2
    local to_version=$3
    local reason=${4:-""}

    local content="**项目**: ${project}\n"
    content+="**原版本**: ${from_version}\n"
    content+="**回滚到**: ${to_version}\n"
    [ -n "${reason}" ] && content+="**原因**: ${reason}"

    send_all_notifications "rollback" "部署回滚 - ${project}" "${content}"
}

# 健康检查失败通知模板
notify_health_check_failure() {
    local project=$1
    local service=$2
    local url=$3
    local attempts=$4

    local content="**项目**: ${project}\n"
    content+="**服务**: ${service}\n"
    content+="**检查地址**: ${url}\n"
    content+="**尝试次数**: ${attempts}"

    send_all_notifications "failure" "健康检查失败 - ${project}" "${content}"
}

# ============================================
# 通知测试
# ============================================

# 测试通知配置
test_notification() {
    local channel=$1

    log_info "测试通知渠道: ${channel}"

    send_notification "${channel}" "info" "测试通知" "这是一条测试通知消息，发送时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

# 测试所有通知渠道
test_all_notifications() {
    log_info "测试所有通知渠道..."

    test_notification "email"
    test_notification "dingtalk"
    test_notification "slack"
    test_notification "wechat"
    test_notification "feishu"
}

# 导出所有函数
export -f send_notification send_all_notifications
export -f get_status_icon get_status_color build_notification_message
export -f send_email_notification send_email_curl
export -f send_dingtalk_notification send_dingtalk_text send_dingtalk_actioncard
export -f send_slack_notification send_slack_simple
export -f send_wechat_notification send_wechat_text
export -f send_feishu_notification send_feishu_text get_feishu_template
export -f send_webhook_notification
export -f notify_deploy_success notify_deploy_failure notify_rollback notify_health_check_failure
export -f test_notification test_all_notifications
