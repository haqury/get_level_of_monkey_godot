netsh advfirewall firewall delete rule name=GetLevelOfAMonkey
netsh advfirewall firewall add rule name=GetLevelOfAMonkey dir=in action=allow program="C:\Users\haqury\Downloads\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64.exe" protocol=TCP localport=17777 profile=any enable=yes
