# mc-heightmapper

A windows command line tool to generate png heightmap images from minecraft worlds.

I wrote the application in Odin on top of my [Odin Nbt Parser](https://github.com/SessizLeylek/odin-nbt) since i needed such an application but couldn't find anywhere.

## Usage

Here is an example usage of the application:

```powershell
# The world name should be identical to the folder name in .minecraft\saves folder
Enter the world folder name: balkent 
Which dimension? (0: Overworld, 1: Nether, 2: The End): 0
# Since the range of a color channel in a png is 0..255 and minecraft build limits are -64..319, 
# You have to specificy the lower bound of the heightmap in minecraft coordinates, such as 62 for water level
Minimum block height you want (That height and the blocks lower will be colored to pitch black): 40

Submit nothing to continue.
# Write region coordinates as space separated
Write a region you want the heightmap of (i.e. "-3 -2"): -2 0	
Write a region you want the heightmap of (i.e. "-3 -2"): -1 0
Write a region you want the heightmap of (i.e. "-3 -2"): 0 0
Write a region you want the heightmap of (i.e. "-3 -2"): 1 0
# Write nothing to submit
Write a region you want the heightmap of (i.e. "-3 -2"): 
Successfully saved image: .\r.-2.0.png
Successfully saved image: .\r.-1.0.png
Successfully saved image: .\r.0.0.png
Successfully saved image: .\r.1.0.png
```
