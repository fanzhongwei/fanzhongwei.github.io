---
title: Hexo 下拉刷新
date: 2019-06-21
tags: 
	- Hexo
	- pull refresh
	- 下拉刷新
categories:
	- Hexo
---

现在手机上大部分的app、网页都具备下拉刷新的功能，用着还挺爽的。

最近基于Hexo搭建的个人博客网站，默认居然不支持下拉刷新，索性就自己手动弄了一个下拉刷新。

![ZSUqoT.png](https://s2.ax1x.com/2019/06/21/ZSUqoT.png)

<!-- more -->

# 为什么要下拉刷新

现在浏览器不都有自带的刷新功能么？

原因如下：
- 相较于点击右上角刷新按钮（还有可能要点两次，第一次先展开 menu bar，然后才能看到 refresh 按钮），直接了当地下拉刷新无疑提供了更好的用户体验
- 点击刷新按钮同步重载页面必然存在一定白屏时间，而通过下拉刷新的逻辑完全可以对于页面内容进行异步更新，其体验毫无疑问更加优秀
- 移动端特有 touch 相关事件，用户在移动设备上的触摸、滑动操作频繁，习惯已经养成，下拉刷新在提供更好的体验的同时，丝毫没有增加用户的学习成本
- 很多内容 + 社交的业务场景里面，主页面的存留时长极高且内容实时性强（如微博、知乎、头条等）, 这些 Native App 已经普遍向用户提供了这种(下拉刷新)更新页面内容的交互方式。作为一个 Web 开发者，如有志于在移动领域让 Web App 和 Native App 在体验方面一较高下，那 H5 页（异步）下拉刷新功能也算是不可或缺的一环
- 当然，还可以应对一些特殊场景 … （如 Webview 不提供刷新按钮 =,=）

# 如何添加

GitHub上找了很多类似的轮子，最终决定采用mescroll，下面就基于mescroll来实现hexo博客的下拉刷新功能。

## 下载mescroll

到mescroll官网下载，[mescroll.min.css,mescroll.min.js](http://www.mescroll.com/load.html)文件，放到themes/next/source/lib/mescroll文件夹下。

api文档请参考：http://www.mescroll.com/api.html?v=190426

## 引入js文件和css文件

修改themes/next/layout/_custom/head.swig文件，添加如下内容：
```
{#
Custom head.
#}

<link rel="stylesheet" href="{{ url_for(theme.vendors._internal + '/mescroll/mescroll.min.css?v=1.4.1') }}"/>
<script src="{{ url_for(theme.vendors._internal + '/mescroll/mescroll.min.js?v=1.4.1') }}" charset="utf-8"></script>
```
这样就能将js和css文件引入到HTML页面中。

## 使用

根据mescroll的api文档添加pull-refresh.js文件：
```javascript
$(function(){
  new MeScroll('body',{
      down: {
        callback: function(){
          window.location.reload();
        }
      }
    });
});
```
存放在：themes/next/source/js/pull-refresh.js路径下，然后将其引入到HTML页面中，修改themes/next/layout/_scripts/commons.swig文件，将pull-refresh.js文件引入进去。
```
{%
  set js_commons = [
    'utils.js',
    'motion.js',
    'pull-refresh.js'
  ]
%}

{% for common in js_commons %}
  <script src="{{ url_for(theme.js) }}/{{ common }}?v={{ version }}"></script>
{% endfor %}
```
这里只所以不将pull-refresh.js一并放到head.swig文件中，是因为其中引用的jQuery引入顺序在head.swig之后。

到这里本来以为搞定了，结果打开页面发现页面会不停地刷新，然后调试源代码，发现mescroll初始的时候会根据配置自动刷新一次：

mescroll.min.js
```javascript
setTimeout(function() {
    if (h.optDown.use && h.optDown.auto && f) {
        if (h.optDown.autoShowLoading) {
            h.triggerDownScroll()
        } else {
            h.optDown.callback && h.optDown.callback(h)
        }
    }
    h.optUp.use && h.optUp.auto && !h.isUpAutoLoad && h.triggerUpScroll()
}, 30)
```
于是乎修改mescroll的初始化代码：
```javascript
$(function(){
  new MeScroll('body',{
      down: {
        callback: function(){
          window.location.reload();
        },
        auto: false
      }
    });
});
```
至此，下拉刷新终于搞定了。

后来查看mescroll的[参数说明](http://www.mescroll.com/api.html?v=190426#options)，发现里面有提到auto的含义，这个故事告诉我们，使用前尽量多看看文档，也许能节省不少的时间。



参考链接

http://www.mescroll.com/index.html

https://hexo.io/zh-cn/docs/

