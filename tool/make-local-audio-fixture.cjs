// Audio sintetis untuk uji impor offline; tidak disertakan sebagai katalog aplikasi.
const fs = require('node:fs');
const rate = 8000, seconds = 120, samples = rate * seconds;
const wav = Buffer.alloc(44 + samples * 2);
wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4);
wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 2, 28);
wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(samples * 2, 40);
for (let i = 0; i < samples; i++) {
  const fade = Math.min(1, i / rate, (samples - i) / rate);
  wav.writeInt16LE(Math.round(Math.sin(2 * Math.PI * 440 * i / rate) * 3000 * fade), 44 + i * 2);
}
fs.mkdirSync('build', { recursive: true });
fs.writeFileSync('build/Swift Local Test.wav', wav);
console.log('Created build/Swift Local Test.wav (120 seconds, PCM WAV).');
