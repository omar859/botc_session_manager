const fs = require('fs');
const path = 'assets/web_client/index.html';
const text = fs.readFileSync(path, 'utf8');
const m = text.match(/<script>([\s\S]*)<\/script>/);
if (!m) throw new Error('No script tag found');
const js = m[1];
try {
  new Function(js);
  const checks = [
    /neighborDmMessages:\s*\{\}/.test(text),
    /unreadNeighborDmPeerIds:\s*new Set\(\)/.test(text),
    /viewingNeighborPeerId:\s*null/.test(text),
    /case 'neighbor_dm_message'/.test(js),
    /case 'neighbor_dm_sync'/.test(js),
  ];
  console.log('JS syntax OK');
  console.log(JSON.stringify(checks));
  if (!checks.every(Boolean)) process.exit(1);
} catch (e) {
  console.error(e.stack || e.message);
  process.exit(1);
}
