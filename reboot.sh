#!/bin/bash

echo 'Update remote code!'

git fetch --all  
git reset --hard origin/master 
git pull


APP_NAME=hexo

tpid=`ps -ef|grep $APP_NAME|grep -v grep|grep -v kill|awk '{print $2}'`
if [ -n "$tpid" ];
then
    echo 'Stop hexo server Process...'
    kill -15 $tpid
fi
sleep 5
tpid=`ps -ef|grep $APP_NAME|grep -v grep|grep -v kill|awk '{print $2}'`
if [ -n "$tpid" ];
then
    echo 'Kill hexo server Process!'
    kill -9 $tpid
else
    echo 'Stop hexo server Success!'
fi

echo 'Start hexo server and listening 80 port...'

nohup hexo server -p 80 > blog.out 2>&1 &

echo 'Hexo server is started!'