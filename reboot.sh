#!/bin/bash

echo 'Update remote code!'

git fetch --all  
git reset --hard origin/master 
git pull

sudo clean
sudo hexo g


/usr/local/nginx/sbin/nginx -s stop

/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf

echo 'Hexo server is started!'