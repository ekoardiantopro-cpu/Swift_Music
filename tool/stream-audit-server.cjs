// Local-only integration fixture, not a production streaming backend.
const http = require('node:http');
const rate = 22050, seconds = 60, count = rate * seconds;
const wave = Buffer.alloc(44 + count * 2);
wave.write('RIFF',0); wave.writeUInt32LE(wave.length-8,4); wave.write('WAVEfmt ',8);
wave.writeUInt32LE(16,16); wave.writeUInt16LE(1,20); wave.writeUInt16LE(1,22);
wave.writeUInt32LE(rate,24); wave.writeUInt32LE(rate*2,28); wave.writeUInt16LE(2,32); wave.writeUInt16LE(16,34);
wave.write('data',36); wave.writeUInt32LE(count*2,40);
for(let i=0;i<count;i++) wave.writeInt16LE(Math.round(500*Math.sin(2*Math.PI*220*i/rate)),44+i*2);
const server=http.createServer((req,res)=>{
  if(req.url==='/radio.m3u') { res.writeHead(200,{'Content-Type':'audio/x-mpegurl'}); res.end('#EXTM3U\n#EXTINF:60,Network Audit\nhttp://127.0.0.1:18765/test.wav\n'); return; }
  if(req.url==='/test.lrc') { res.writeHead(200,{'Content-Type':'text/plain; charset=utf-8'}); res.end('[00:00.00]Swift Music network playback test\n[00:10.00]HTTP stream and lyrics\n'); return; }
  if(req.url!=='/test.wav') { res.writeHead(404); res.end(); return; }
  const range=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range||'');
  const start=range?Number(range[1]):0, end=range&&range[2]?Math.min(Number(range[2]),wave.length-1):wave.length-1;
  if(start>end || start>=wave.length) { res.writeHead(416); res.end(); return; }
  const headers={'Content-Type':'audio/wav','Content-Length':end-start+1,'Accept-Ranges':'bytes'};
  if(range) headers['Content-Range']=`bytes ${start}-${end}/${wave.length}`;
  res.writeHead(range?206:200,headers); res.end(wave.subarray(start,end+1));
});
server.listen(18765,'127.0.0.1',()=>process.stdout.write('Swift network audit fixture listening on localhost:18765\n'));
process.on('SIGINT',()=>server.close());
