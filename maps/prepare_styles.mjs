import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const vendorDirectory = process.argv[2];
const outputDirectory = process.argv[3];

if (!vendorDirectory || !outputDirectory) {
  throw new Error(
    'Usage: node prepare_styles.mjs <vendor-styles-directory> <output-directory>',
  );
}

const iraqBounds = [38.7936, 29.0612, 48.5759, 37.3809];
const baghdadCenter = [44.3661, 33.3152];

const styles = [
  {
    input: join(vendorDirectory, 'colorful', 'style.json'),
    output: 'jowla-day.json',
    name: 'Jowla Iraq Day',
  },
];

mkdirSync(outputDirectory, { recursive: true });

for (const definition of styles) {
  const style = JSON.parse(readFileSync(definition.input, 'utf8'));
  style.name = definition.name;
  style.center = baghdadCenter;
  style.zoom = 5.5;
  style.sprite = [{ id: 'basics', url: 'basics/sprites' }];
  style.glyphs = '{fontstack}/{range}.pbf';
  style.sources = {
    'versatiles-shortbread': {
      type: 'vector',
      url: 'mbtiles://{iraq}',
      attribution:
        '© OpenStreetMap contributors · Geofabrik · VersaTiles contributors',
      bounds: iraqBounds,
      minzoom: 0,
      maxzoom: 14,
    },
  };

  writeFileSync(
    join(outputDirectory, definition.output),
    `${JSON.stringify(style, null, 2)}\n`,
  );
}
