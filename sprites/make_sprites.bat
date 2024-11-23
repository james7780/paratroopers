rem Convert player sprites from spritesheet
rem Literal, 4 BPP

rem Player base
sprpck -s4 -t6 -u -o020000 -S015013 -a006012 spritesheet2.bmp base.spr

rem gun barrels
sprpck -s4 -t6 -u -o000000 -S018010 -a008008 spritesheet2.bmp gun0.spr
sprpck -s4 -t6 -u -o000010 -S018010 -a008008 spritesheet2.bmp gun1.spr
sprpck -s4 -t6 -u -o000020 -S018010 -a008008 spritesheet2.bmp gun2.spr
sprpck -s4 -t6 -u -o000030 -S018010 -a008008 spritesheet2.bmp gun3.spr
sprpck -s4 -t6 -u -o000040 -S018010 -a008008 spritesheet2.bmp gun4.spr
sprpck -s4 -t6 -u -o000050 -S018010 -a008008 spritesheet2.bmp gun5.spr
sprpck -s4 -t6 -u -o000060 -S018010 -a008008 spritesheet2.bmp gun6.spr
sprpck -s4 -t6 -u -o000070 -S018010 -a008008 spritesheet2.bmp gun7.spr
sprpck -s4 -t6 -u -o000080 -S018010 -a008008 spritesheet2.bmp gun8.spr
sprpck -s4 -t6 -u -o000090 -S018010 -a008008 spritesheet2.bmp gun9.spr
sprpck -s4 -t6 -u -o000100 -S018010 -a008008 spritesheet2.bmp gun10.spr
sprpck -s4 -t6 -u -o000110 -S018010 -a008008 spritesheet2.bmp gun11.spr
sprpck -s4 -t6 -u -o020020 -S018010 -a008008 spritesheet2.bmp gun12.spr
sprpck -s4 -t6 -u -o020030 -S018010 -a008008 spritesheet2.bmp gun13.spr
sprpck -s4 -t6 -u -o020040 -S018010 -a008008 spritesheet2.bmp gun14.spr
sprpck -s4 -t6 -u -o020050 -S018010 -a008008 spritesheet2.bmp gun15.spr
sprpck -s4 -t6 -u -o020060 -S018010 -a008008 spritesheet2.bmp gun16.spr

copy /B gun0.spr + gun1.spr + gun2.spr + gun3.spr + gun4.spr + gun5.spr + gun6.spr + gun7.spr + gun8.spr + gun9.spr + gun10.spr + gun11.spr + gun12.spr + gun13.spr + gun14.spr + gun15.spr + gun16.spr gunArray.spr

rem Convert enemy sprites from spritesheet
sprpck -s4 -t6 -u -o016016 -S005004 -a001001 spritesheet.bmp bullet.spr

sprpck -s4 -t6 -u -o064000 -S032010 -a015005 spritesheet.bmp heli1.spr
sprpck -s4 -t6 -u -o064010 -S032010 -a015005 spritesheet.bmp heli2.spr

sprpck -s4 -t6 -u -o020032 -S013013 -a006009 spritesheet.bmp chute1.spr
sprpck -s4 -t6 -u -o020048 -S013013 -a006009 spritesheet.bmp chute2.spr
sprpck -s4 -t6 -u -o020064 -S013013 -a006009 spritesheet.bmp chute3.spr
sprpck -s4 -t6 -u -o020080 -S013013 -a006009 spritesheet.bmp chute4.spr
copy /B chute1.spr + chute2.spr + chute3.spr + chute4.spr chuteArray.spr

sprpck -s4 -t6 -u -o020112 -S007006 -a002002 spritesheet.bmp trooper1.spr
sprpck -s4 -t6 -u -o020096 -S007006 -a002002 spritesheet.bmp fall.spr
sprpck -s4 -t6 -u -o034112 -S007006 -a002002 spritesheet.bmp run1.spr
sprpck -s4 -t6 -u -o034122 -S007006 -a002002 spritesheet.bmp run2.spr

sprpck -s4 -t6 -u -o096000 -S007006 -a003003 spritesheet.bmp frag1.spr
sprpck -s4 -t6 -u -o096010 -S007006 -a003003 spritesheet.bmp frag2.spr
sprpck -s4 -t6 -u -o096020 -S007006 -a003003 spritesheet.bmp frag3.spr
sprpck -s4 -t6 -u -o096030 -S007006 -a003003 spritesheet.bmp frag4.spr
copy /B frag1.spr + frag2.spr + frag3.spr + frag4.spr fragArray.spr

rem Bomber and bomb
sprpck -s4 -t6 -u -o064032 -S032009 -a015006 spritesheet.bmp bomber1.spr
sprpck -s4 -t6 -u -o064048 -S032009 -a015006 spritesheet.bmp bomber2.spr
sprpck -s4 -t6 -u -o100048 -S004006 -a001003 spritesheet.bmp bomb.spr

rem Title sprite
sprpck -s4 -t6 -u -o000000 -S083046 -a000000 title2.bmp title2.spr

rem Clean up
del *.pal



