const fs = require('fs');
const Spritesmith = require('spritesmith');

const sprites = fs.readdirSync('./img').filter(f => f.endsWith('.png'));

Spritesmith.run({
  src: sprites.map(f => `./img/${f}`),
  algorithm: 'binary-tree',
  padding: 2
}, (err, result) => {
  // Save spritesheet
  fs.writeFileSync('spritesheet.png', result.image);
  
  // Generate CSS
  let css = '';
  Object.keys(result.coordinates).forEach(file => {
    const coords = result.coordinates[file];
    const name = file.replace('.png', '').replace('./img/', '');
    css += `.${name} {
      background-position: -${coords.x}px -${coords.y}px;
      width: ${coords.width}px;
      height: ${coords.height}px;
    }\n`;
  });
  
  fs.writeFileSync('sprites.css', css);
});