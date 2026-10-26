// Regenerates the opaque SpringBoard icon set from the supplied 音频.svg.
// Requires: npm install sharp (run with NODE_PATH pointing at that install).
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'artwork', '音频.svg'), 'utf8')
  .replace(/#6B400D/g, '#F4E4C4')
  .replace(/#FFD524/g, '#F0B33F');

(async () => {
  const size = 1024;
  const art = await sharp(Buffer.from(source), { density: 384 })
    .resize(760, 760, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  const background = Buffer.from(`<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg"><defs><radialGradient id="g" cx="26%" cy="18%" r="82%"><stop offset="0" stop-color="#3A2617"/><stop offset="0.58" stop-color="#24170E"/><stop offset="1" stop-color="#150E09"/></radialGradient></defs><rect width="${size}" height="${size}" fill="url(#g)"/></svg>`);

  const master = await sharp(background)
    .composite([{ input: art, left: 132, top: 132 }])
    .flatten({ background: '#24170E' })
    .removeAlpha()
    .png()
    .toBuffer();

  const outputs = {
    'AppIcon20x20@2x.png': 40,
    'AppIcon20x20@3x.png': 60,
    'AppIcon29x29@2x.png': 58,
    'AppIcon29x29@3x.png': 87,
    'AppIcon40x40@2x.png': 80,
    'AppIcon40x40@3x.png': 120,
    'AppIcon60x60.png': 60,
    'AppIcon60x60@2x.png': 120,
    'AppIcon60x60@3x.png': 180,
    'AppIcon76x76@2x.png': 152,
    'AppIcon83.5x83.5@2x.png': 167,
    'AppIcon1024.png': 1024,
  };
  for (const [name, px] of Object.entries(outputs)) {
    await sharp(master).resize(px, px, { kernel: 'lanczos3' }).png().toFile(path.join(root, 'Resources', name));
  }
  fs.writeFileSync(path.join(root, 'Resources', 'AppIcon1024.png'), await sharp(master).png().toBuffer());
  console.log('icons written');
})();
