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
