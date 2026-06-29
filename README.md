# Ground-Demo

## Description
Procedural Terrain Generator written in C# and GD script on a separate branch. 
Generation is controlled by json files to control biome and decoration's properties. 
Lists of biome, decors and textures can be easily expanded.

## Configuration
### Textures
File Assets/Ground/textures/texture_values.json contains list of images stored in this folder. It is important to decide the placement if a texture in a list. When referencing a texture take its number in a list (beginning from 0)

### Decoration
File Assets/Ground/decors/decor_values.json decides what objects can be placed on the ground and in what condition. each entry in this file, should have a corrsponden godot scene file (tscn) with name corresponding to DecorName json variable. It's possible to call a script on spawning a decoration, by defining a script and defining its path in GeneratorScriptFields json property. Consult House decor as an example. Fields in this json file correspond to fields in Ground/GroundInfos/DecorInfo.cs. Reference it for more details about the configuration fields.

## Biomes
File Assets/Ground/biomes/biome_values.json defines biome properties, also parts of the ground with a different properties, like size, decorations or textures. It is also possible to have water present in a biome, if HasWater property is true and Offset property is below 0. Consult Lake biome as an example. Fields in this json file correspond to fields in Ground/GroundInfos/BiomeInfo.cs. Reference it for more details about the configuration fields.

## Credits
- Mob navigation logic was inspired by https://github.com/TokisanGames/Terrain3D
- Textures:
  - grass texture: shutterstock.com/image-illustration/seamless-cartoon-stylized-texture-dense-light-1961014570
  - mud texture: https://www.craiyon.com/de/image/ldPG27CRTlqZ4KQw9bgGNg
  - path texture: https://www.shutterstock.com/image-illustration/view-above-cartoon-stone-on-grass-542584729
  - rock texture: https://www.shutterstock.com/image-photo/warm-limestone-texture-159548051
- AI disclosure: AI has been used to help debug code problems and solve complex code problems, like writing a gdshader for applying biome dependant textures to the ground.
- All other assets, including 3D models and code has been made by me.
