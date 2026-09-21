:local qDL "Global-Download"
:local qUL "Global-Upload"
:local dlMin 120000000
:local dlStart 220000000
:local dlMax 249735037
:local ulMin 15000000
:local ulStart 27000000
:local ulMax 32000000
:local growStep 3
:local downStep 4
:local criticalDownStep 7
:local emaCurrent 20
:local emaPrevious 80
:local utilGrow 78
:local utilCongest 90
:local utilCritical 96
:local queueWarn 262144
:local queueCritical 524288
:local growCycles 3
:local congestCycles 2
:local criticalCycles 2
:local cooldownCycles 3
:global V9Lock
:global V9Cycle
:global V9EmaDL
:global V9EmaUL
:global V9StableDL
:global V9StableUL
:global V9CongestDL
:global V9CongestUL
:global V9CriticalDL
:global V9CriticalUL
:global V9LastDL
:global V9LastUL
:global V9StateDL
:global V9StateUL
:global V9LastDlDrop
:global V9LastUlDrop
:if ([:typeof $V9Lock] = "nothing") do={ :set V9Lock false }
:if ([:typeof $V9Cycle] = "nothing") do={ :set V9Cycle 0 }
:if ([:typeof $V9EmaDL] = "nothing") do={ :set V9EmaDL 0 }
:if ([:typeof $V9EmaUL] = "nothing") do={ :set V9EmaUL 0 }
:if ([:typeof $V9StableDL] = "nothing") do={ :set V9StableDL 0 }
:if ([:typeof $V9StableUL] = "nothing") do={ :set V9StableUL 0 }
:if ([:typeof $V9CongestDL] = "nothing") do={ :set V9CongestDL 0 }
:if ([:typeof $V9CongestUL] = "nothing") do={ :set V9CongestUL 0 }
:if ([:typeof $V9CriticalDL] = "nothing") do={ :set V9CriticalDL 0 }
:if ([:typeof $V9CriticalUL] = "nothing") do={ :set V9CriticalUL 0 }
:if ([:typeof $V9LastDL] = "nothing") do={ :set V9LastDL -100 }
:if ([:typeof $V9LastUL] = "nothing") do={ :set V9LastUL -100 }
:if ([:typeof $V9StateDL] = "nothing") do={ :set V9StateDL "stable" }
:if ([:typeof $V9StateUL] = "nothing") do={ :set V9StateUL "stable" }
:if ([:typeof $V9LastDlDrop] = "nothing") do={ :set V9LastDlDrop 0 }
:if ([:typeof $V9LastUlDrop] = "nothing") do={ :set V9LastUlDrop 0 }
:if ($V9Lock = true) do={ :log warning "DynBW V9: stale lock"; :set V9Lock false }
:set V9Lock true
:set V9Cycle ($V9Cycle + 1)
:local idDL [/queue tree find name=$qDL]
:local idUL [/queue tree find name=$qUL]
:if ([:len $idDL] = 0) do={ :set V9Lock false; :error "V9: no DL" }
:if ([:len $idUL] = 0) do={ :set V9Lock false; :error "V9: no UL" }
:local curDL [/queue tree get $idDL max-limit]
:local curUL [/queue tree get $idUL max-limit]
:local dlRate 0; :local dlQueued 0; :local ulRate 0; :local ulQueued 0
:foreach q in=[/queue tree find parent=$qDL] do={ :set dlRate ($dlRate + [/queue tree get $q rate]); :set dlQueued ($dlQueued + [/queue tree get $q queued-bytes]) }
:foreach q in=[/queue tree find parent=$qUL] do={ :set ulRate ($ulRate + [/queue tree get $q rate]); :set ulQueued ($ulQueued + [/queue tree get $q queued-bytes]) }
:local dlDropped [/queue tree get $idDL dropped]
:local ulDropped [/queue tree get $idUL dropped]
:local dlDropDelta ($dlDropped - $V9LastDlDrop)
:local ulDropDelta ($ulDropped - $V9LastUlDrop)
:if ($dlDropDelta < 0) do={ :set dlDropDelta 0 }
:if ($ulDropDelta < 0) do={ :set ulDropDelta 0 }
:set V9LastDlDrop $dlDropped
:set V9LastUlDrop $ulDropped
:local dlUtil 0; :local ulUtil 0
:if ($curDL > 0) do={ :set dlUtil (($dlRate * 100) / $curDL) }
:if ($curUL > 0) do={ :set ulUtil (($ulRate * 100) / $curUL) }
:if ($dlUtil > 100) do={ :set dlUtil 100 }
:if ($ulUtil > 100) do={ :set ulUtil 100 }
:if ($V9EmaDL = 0) do={ :set V9EmaDL $dlUtil } else={ :set V9EmaDL ((($dlUtil * $emaCurrent) + ($V9EmaDL * $emaPrevious)) / 100) }
:if ($V9EmaUL = 0) do={ :set V9EmaUL $ulUtil } else={ :set V9EmaUL ((($ulUtil * $emaCurrent) + ($V9EmaUL * $emaPrevious)) / 100) }
:local dlCritical false; :local dlCongest false; :local dlStable false
:if (($V9EmaDL >= $utilCritical) && ($dlQueued >= $queueCritical)) do={ :set dlCritical true }
:if ((($V9EmaDL >= $utilCongest) && ($dlQueued >= $queueWarn)) || ($dlDropDelta > 100)) do={ :set dlCongest true }
:if (($V9EmaDL >= $utilGrow) && ($dlQueued < $queueWarn) && ($dlDropDelta = 0)) do={ :set dlStable true }
:local ulCritical false; :local ulCongest false; :local ulStable false
:if (($V9EmaUL >= $utilCritical) && ($ulQueued >= $queueCritical)) do={ :set ulCritical true }
:if ((($V9EmaUL >= $utilCongest) && ($ulQueued >= $queueWarn)) || ($ulDropDelta > 100)) do={ :set ulCongest true }
:if (($V9EmaUL >= $utilGrow) && ($ulQueued < $queueWarn) && ($ulDropDelta = 0)) do={ :set ulStable true }
:if ($dlCritical) do={ :set V9CriticalDL ($V9CriticalDL+1); :set V9CongestDL 0; :set V9StableDL 0 } else={ :set V9CriticalDL 0; :if ($dlCongest) do={ :set V9CongestDL ($V9CongestDL+1); :set V9StableDL 0 } else={ :set V9CongestDL 0; :if ($dlStable) do={ :set V9StableDL ($V9StableDL+1) } else={ :set V9StableDL 0 } } }
:if ($ulCritical) do={ :set V9CriticalUL ($V9CriticalUL+1); :set V9CongestUL 0; :set V9StableUL 0 } else={ :set V9CriticalUL 0; :if ($ulCongest) do={ :set V9CongestUL ($V9CongestUL+1); :set V9StableUL 0 } else={ :set V9CongestUL 0; :if ($ulStable) do={ :set V9StableUL ($V9StableUL+1) } else={ :set V9StableUL 0 } } }
:local dlCooldown false; :local ulCooldown false
:if (($V9Cycle - $V9LastDL) < $cooldownCycles) do={ :set dlCooldown true }
:if (($V9Cycle - $V9LastUL) < $cooldownCycles) do={ :set ulCooldown true }
:local newDL $curDL; :local newUL $curUL
:if ($curDL < $dlMin) do={ :set newDL $dlMin }
:if ($curDL > $dlMax) do={ :set newDL $dlMax }
:if ($curUL < $ulMin) do={ :set newUL $ulMin }
:if ($curUL > $ulMax) do={ :set newUL $ulMax }
:if ($V9Cycle = 1) do={ :set newDL $dlStart; :set newUL $ulStart }
:if ($V9Cycle > 1) do={ :if ($V9CriticalDL >= $criticalCycles) do={ :set newDL ($curDL-(($curDL*$criticalDownStep)/100)); :if ($newDL<$dlMin) do={:set newDL $dlMin}; :set V9StateDL "critical" } else={ :if (($V9CongestDL>=$congestCycles)&&($dlCooldown=false)) do={ :set newDL ($curDL-(($curDL*$downStep)/100)); :if ($newDL<$dlMin) do={:set newDL $dlMin}; :set V9StateDL "congested" } else={ :if (($V9StableDL>=$growCycles)&&($dlCooldown=false)) do={ :set newDL ($curDL+(($curDL*$growStep)/100)); :if ($newDL>$dlMax) do={:set newDL $dlMax}; :set V9StateDL "growing" } else={ :set V9StateDL "stable" } } }; :if ($V9CriticalUL>=$criticalCycles) do={ :set newUL ($curUL-(($curUL*$criticalDownStep)/100)); :if ($newUL<$ulMin) do={:set newUL $ulMin}; :set V9StateUL "critical" } else={ :if (($V9CongestUL>=$congestCycles)&&($ulCooldown=false)) do={ :set newUL ($curUL-(($curUL*$downStep)/100)); :if ($newUL<$ulMin) do={:set newUL $ulMin}; :set V9StateUL "congested" } else={ :if (($V9StableUL>=$growCycles)&&($ulCooldown=false)) do={ :set newUL ($curUL+(($curUL*$growStep)/100)); :if ($newUL>$ulMax) do={:set newUL $ulMax}; :set V9StateUL "growing" } else={ :set V9StateUL "stable" } } } }
:if ($newDL != $curDL) do={ :do { /queue tree set $idDL max-limit=$newDL; :set V9LastDL $V9Cycle; :log info ("DynBW V9 DL ".($curDL/1000000)."M->".($newDL/1000000)."M U=".$dlUtil."% E=".$V9EmaDL."% S=".$V9StateDL) } on-error={ :log error "V9 DL fail" } }
:if ($newUL != $curUL) do={ :do { /queue tree set $idUL max-limit=$newUL; :set V9LastUL $V9Cycle; :log info ("DynBW V9 UL ".($curUL/1000000)."M->".($newUL/1000000)."M U=".$ulUtil."% E=".$V9EmaUL."% S=".$V9StateUL) } on-error={ :log error "V9 UL fail" } }
:if (($V9Cycle % 10) = 0) do={ :log info ("DynBW V9 C=".$V9Cycle." DL=".($curDL/1000000)."M/".$dlUtil."%/".$V9StateDL." UL=".($curUL/1000000)."M/".$ulUtil."%/".$V9StateUL) }
:set V9Lock false
