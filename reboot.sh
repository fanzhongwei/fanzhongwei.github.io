#!/bin/bash

git fetch --all  
git reset --hard origin/master 
git pull


APP_NAME=hexo

tpid=`ps -ef|grep $APP_NAME|grep -v grep|grep -v kill|awk '{print $2}'`
if [ -n "$tpid" ];
then
    echo 'Stop Process...'
    kill -15 $tpid
fi
sleep 5
tpid=`ps -ef|grep $APP_NAME|grep -v grep|grep -v kill|awk '{print $2}'`
if [ -n "$tpid" ];
then
    echo 'Kill Process!'
    kill -9 $tpid
else
    echo 'Stop Success!'
fi


nohup hexo server -p 80 > blog.out 2>&1 &