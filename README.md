apk-static-xref
=======

apk-static-xref is a project that staticallly generate a cross-reference-graph 
(XRG) of a component (e.g., Service) of Android apk file. And plot a CFG by 
ruby-graphviz as you expected.

This work is writing by ruby, some code of the first version is from Redexer 
ruby script and smali-cfg python codes.

Requirements
------------

* Ruby
* graphviz dot and ruby-graphviz
* Android SDK (or sources)
* apktool.jar
* RubyGems and Nokogiri

Usage
-----

To get help:

	$ ruby script/xref.rb -h

To get specific cls->mtd(para)r xref:

    $ ruby script/xref.rb test/beanbot.apk -a --cmd xref --cls "com/android/providers/sms/SMSService" --mtd "onStart" --pty "(Landroid/content/Intent;I)V" [-v] [-g]

To get a specific class xref:

	$ ruby script/xref.rb test/beanbot.apk -a --cmd xref --cls "com/android/providers/sms/SMSService" [-v] [-g]

To get the overall apk services xref:

    $ ruby script/xref.rb test/beanbot.apk --cmd xref --cpt service [-v] [-g]
    
To get the overall apk activity xref:

    $ ruby script/xref.rb test/beanbot.apk --cmd xref --cpt activity [-v] [-g]
    
To generate a overall API invoking of a bunch of APKs:

    $ ruby script/xref-api-generate.rb --apk path-to-apk-directory --xref path-to-xref-directory -v

Reference
-----

Redexer: https://github.com/plum-umd/redexer

smali-cfg: https://code.google.com/p/smali-cfgs
