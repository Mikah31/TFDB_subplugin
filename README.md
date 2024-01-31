# Simple TFDB anticheat
### Purpose
Automatically detecting auto reflect cheats in the TFDB gamemode.

### Current status - Abandoned.
There are too many false detections, whilst it might have some use, it requires a lot of human intervention as it produces a lot of false positives.

### In game commands
"/gaussianstats": Retrieves the mean, standard deviation & total deflections of a player, used for testing purposes.
"/trackdeflects (clientID)": Tracks players deflects & outputs to trackers console. If no args are given display list of clientID's & names.

### Why does it not work?
We rely on the amount of ticks that are passed holding airblast, (some) cheats airblast by writting the IN_ATTACK2 flag for 1 (or 2) tick(s). \
In a perfect world we would see a clear pattern of someone having 1 or 2 ticks coupled with a much higher tick average, however, it seems that due to packetloss, high quality mouses, or some other tf2-weirdness that this detection method does not work.\
A lot of legit players were able to consistently hit lower averages (whilst likely legit), to the point where the efficacy of the detection method was in serious doubt.

### Conclusion
With this plugin we tried to beat the cheat instead of the cheater, cheats could easily (and do) vary the amount of ticks held.
