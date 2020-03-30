#!/bin/bash

echo 'Update remote code!'

git fetch --all  
git reset --hard origin/develop 
git pull

hexo g

hexo deploy

echo 'Hexo server is deployed!'