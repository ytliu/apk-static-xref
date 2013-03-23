on specific cls->mtd(para)r xref:

    $ ruby script/xref.rb test/beanbot.apk -a --cmd xref --cls "com/android/providers/sms/SMSService" --mtd "onStart" --pty "(Landroid/content/Intent;I)V" -v [-g]

on overall xref:

    $ ruby script/xref.rb test/beanboot.apk --cmd xref -v [-g]
    
