#! /bin/bash

iter=5
srce=1
grph=
stime=
otro=

make clean; rm ex_boost; make uplink ff=1               && mv uplink/uplink ex_boost
make clean; rm ex_boost_serial; make uplink serial=1    && mv uplink/uplink ex_boost_serial

echo "Executing graph(num) "$line"("$iter")"
echo "Executing graph(num) "$line"("$iter")" > .aux.txt
echo "#------------------------------------------------ " >> .aux.txt
echo "#ncore  | Demand 1 | Demand 2 | Demand 3 | Serial " >> .aux.txt
echo "#------------------------------------------------ " >> .aux.txt

 for nproc in 1 2 3 4 5 6 7 8 9 10
 do
        echo -n -e " $nproc\t"                  >> .aux.txt
        echo   "./ex_boost      $nproc 1"
                ./ex_boost      $nproc 1 >> .aux.txt && echo -n -e "\t"  >> .aux.txt
        echo   "./ex_boost      $nproc 2"
                ./ex_boost      $nproc 2 >> .aux.txt && echo -n -e "\t"  >> .aux.txt
        echo   "./ex_boost      $nproc 3"
                ./ex_boost      $nproc 3 >> .aux.txt && echo -n -e "\t"  >> .aux.txt
        echo   "./ex_boost_serial"
                ./ex_boost_serial >> .aux.txt && echo ""                >> .aux.txt
 done

mv .aux.txt graphs.txt
