#!/bin/bash
# -------------------------------------------------------------------------------
# version:     2.0
# Description: Spring Boot应用运行脚本，支持Mac,Linux
# -------------------------------------------------------------------------------

#应用主目录
if [ -z "$JAVA_HOME" ]; then
  export JAVA=`which java`
else
  export JAVA="$JAVA_HOME/bin/java"
fi

cd "$(dirname "$0")" || exit 1
APP_HOME=$(pwd)

LOG_DIR="${APP_HOME}/logs"

PID_FILE="${APP_HOME}/app.pid"

BOOT_CONF="${APP_HOME}/boot.properties"

#应用JAR
APP_JAR="$(find "${APP_HOME}" -name "*.jar" 2>/dev/null | head -n 1)"

#应用名称
APP_NAME=${APP_JAR##*/}
RUN_LOG_NAME=${APP_NAME}
APP_NAME=${APP_NAME%.jar}


#操作
ACTION=$1

echoRed() { echo $'\e[0;31m'"$1"$'\e[0m'; }
echoGreen() { echo $'\e[0;32m'"$1"$'\e[0m'; }
echoYellow() { echo $'\e[0;33m'"$1"$'\e[0m'; }

usage() {
	echo $'\n\n\n'
	echoRed "Usage: ${0} support command {start|stop|restart|status|cleanup|deploy}"
	echo $'\n\n\n'
	exit 1
}

psCheck() {
	echo "--------------All instances on this machine--------------"
	echo "USER       PID   %CPU %MEM VSZ    RSS    TTY   STAT  START   TIME COMMAND" && echo ""
	ps aux | grep "$APP_NAME" | grep -E -v "grep"
}

#根据PID_FILE检查是否在运行
isRunning() {
	[[ -f "$PID_FILE" ]] || return 1
	ps -p "$(<"$PID_FILE")" &>/dev/null
}

#1.检查操作参数
[ $# -gt 0 ] || usage

#2.引入启动配置
if [ -r "$BOOT_CONF" ]; then
	. "$BOOT_CONF"
else
	echoRed "Missing or unreadable $BOOT_CONF"
	echo $'\n\n\n'
	exit 1
fi

#基础配置
BASE_ARGS=""
BUILD_JAR="$(find "${BUILD_JAR_DIR}/target" -name "*.jar" 2>/dev/null | head -n 1)"


if [ ! "$DISCOVERY_URI" = "" ]; then
	BASE_ARGS="$BASE_ARGS --eureka.client.serviceUrl.defaultZone=$DISCOVERY_URI"
fi

if [ ! "$PROFILES_ACTIVE" = "" ]; then
	BASE_ARGS="$BASE_ARGS --spring.profiles.active=$PROFILES_ACTIVE"
fi

if [ ! "$SERVER_PORT" = "" ]; then
	BASE_ARGS="$BASE_ARGS --server.port=$SERVER_PORT"
fi

if [ ! "$MAVEN_ARGS" = "" ]; then
	MAVEN_BASE_ARGS="$MAVEN_BASE_ARGS -P $MAVEN_ARGS"
fi

RUN_EXE="$JAVA $JVM_ARGS -jar $APP_JAR $BASE_ARGS $CMD_LINE_ARGS"

start() {
	echo "--------------Starting $APP_NAME:"
	echo $'\n\n\n'

	#检查jdk
	if [ -z "$JAVA" ]; then
		echoRed "Result: Start failed,Cannot find a Java JDK. Please check JAVA_HOME in boot.conf"
		echo $'\n\n\n'
		exit 1
	fi

	#检查已经运行
	if (isRunning); then
		echoYellow "Result: Running, no need to start"
		echo $'\n\n\n'
		exit 0
	fi

	#打印启动命令
	echo "-------Boot Command: "
	echo "nohup $RUN_EXE >${LOG_DIR}/${RUN_LOG_NAME}.run.log 2>${LOG_DIR}/error.log &"
	echo $'\n\n\n'

	#创建错误日志文件
	mkdir -p "$LOG_DIR" && touch "${LOG_DIR}/error.log"

	#启动
	nohup $RUN_EXE >"${LOG_DIR}/${APP_NAME}.run.log" 2>>"${LOG_DIR}/error.log" &

	#记录pid到pid文件
	echo $! >"$PID_FILE"

	#命令执行异常，快速失败
	sleep 0.5
	if (! isRunning); then
		echoRed "Result: Start failed" && rm -f "$PID_FILE"
		echo $'\n\n\n'
		exit 1
	fi

	#启动几秒钟中后失败的情况，6秒内失败
	sleep 6
	if (! isRunning); then
		echoRed "Result: Start failed" && rm -f "$PID_FILE"
		echo $'\n\n\n'
		exit 1
	fi

	#启动几秒钟中后失败的情况，10秒内失败
	sleep 4
	if (! isRunning); then
		echoRed "Result: Start failed" && rm -f "$PID_FILE"
		echo $'\n\n\n'
		exit 1
	fi

	#启动几秒钟中后失败的情况，启动在10秒外失败的比例比较低，而且也不可能一直等，这种情况交给监控告警来解决

	echoGreen "Result: Start success,Running (PID: $(<"$PID_FILE"))"
	echo $'\n\n\n'

	#检查本机存在的实例
	psCheck
}

stop() {
	echo "--------------Stopping $APP_NAME:"
	echo $'\n\n\n'

	if (! isRunning); then
		echoYellow "Result: Not running" && rm -f "$PID_FILE"
		echo $'\n\n\n'
		return 0
	fi

	kill "$(<"$PID_FILE")" 2>/dev/null

	#30秒后强制退出
	TIMEOUT=30
	while isRunning; do
		if ((TIMEOUT-- == 0)); then
			kill -KILL "$(<"$PID_FILE")" 2>/dev/null
		fi
		sleep 1
	done

	rm -f "$PID_FILE"
	echoGreen "Result: Stop success"
	echo $'\n\n\n'
}

status() {
	echo "--------------Status $APP_NAME:"
	echo $'\n\n\n'

	if isRunning; then
		echoGreen "Result: Running （PID: $(<"$PID_FILE"))"
	else
		echoYellow "Result: Not running"
	fi

	echo $'\n\n\n'
	psCheck
}

cleanup() {
	echo "--------------Cleanup $APP_NAME:"
	echo $'\n\n\n'
	if ! isRunning; then
		[[ -d "$LOG_DIR" ]] || {
			echoGreen "Result: Log does not exist, there is no need to clean up" && echo $'\n\n\n'
			return 0
		}
		rm -rf "$LOG_DIR"
		echoGreen "Result: Log cleared"
	else
		echoYellow "Result: Please stop the application first and then clean up the log"
	fi
	echo $'\n\n\n'
}

function gitpull(){
	echo "--------------gitpull $APP_NAME:"
	echo $APP_GIT_REPO_DIR
	cd $APP_GIT_REPO_DIR
	
	[[ -f "update.sh" ]] 
	if [ -f "update.sh" ]; then
	   sh update.sh
	else
	   git pull
	fi
}

function checkout(){
	echo "--------------checkout $APP_NAME:"
	echo $APP_GIT_REPO_DIR
	cd $APP_GIT_REPO_DIR
	git checkout $BRANCH_NAME
}

function package(){
	echo "--------------package $APP_NAME:"
	cd $APP_GIT_REPO_DIR
	echo "-------------- MAVEN_BASE_ARGS ${MAVEN_BASE_ARGS}"
	mvn clean install -Dmaven.test.skip=true $MAVEN_BASE_ARGS
}

function copy() {
	echo -e "Copying jar files from ${BUILD_JAR} to ${APP_HOME} "
	echo "${APP_JAR}"
	rm -f ${APP_JAR}

	cp -rfv ${BUILD_JAR} ${APP_HOME}/
}

function deploy(){
	echo "--------------deploy $APP_NAME:"
	stop
	#checkout
	#gitpull
	package
	copy
	start
}

case "$ACTION" in
deploy)
    deploy
	;;
start)
	start
	;;
stop)
	stop
	;;
restart)
	stop
	start
	;;
status)
	status
	;;
cleanup)
	cleanup
	;;
*)
	usage
	;;
esac

#成功退出
exit 0

