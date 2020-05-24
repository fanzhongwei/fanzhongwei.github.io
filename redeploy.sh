#!/bin/bash

echo 'Update remote code!'

git pull

hexo g

hexo deploy

echo 'Hexo server is deployed!'