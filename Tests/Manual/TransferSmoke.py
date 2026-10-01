from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import threading, time, subprocess, os, json, tempfile
started = threading.Event()
class Handler(BaseHTTPRequestHandler):
 def log_message(self, *args): pass
 def do_GET(self):
  if self.path == '/started':
   body=b'yes' if started.is_set() else b'no'
  elif self.path == '/api/me':
   started.set(); time.sleep(0.5)
   body=json.dumps({'ok':True,'data':{'user':{'id':7,'username':'fixture'},'csrf':'fixture','server_time':1}}).encode()
  else:
   body=b'x' * (512 if self.path == '/small' else 8*1024*1024)
  self.send_response(200)
  if self.path != '/unknown': self.send_header('Content-Length',str(len(body)))
  else: self.send_header('Connection','close'); self.close_connection=True
  self.end_headers()
  try:
   for offset in range(0,len(body),16384):
    self.wfile.write(body[offset:offset+16384]); self.wfile.flush()
    if len(body)>1024: time.sleep(0.002)
  except (BrokenPipeError,ConnectionResetError): pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
base='http://127.0.0.1:'+str(server.server_port)
root = Path(__file__).resolve().parents[2]
env = os.environ.copy()
if 'DEVELOPER_DIR' not in env and Path('/Applications/Xcode.app').exists():
 env['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
try:
 with tempfile.TemporaryDirectory(prefix='plainwire-transfer-smoke-') as scratch:
  source = Path(__file__).with_suffix('.swift').read_text().replace('FIXTURE_BASE_URL',base)
  swift = Path(scratch) / 'TransferSmoke.swift'
  swift.write_text(source)
  executable = Path(scratch) / 'TransferSmoke'
  subprocess.run(['xcrun','swiftc','-swift-version','6','-parse-as-library',
    *[str(p) for p in (root / 'Sources/PlainwireCore').glob('*.swift')],str(swift),'-o',str(executable)],
    check=True, env=env, timeout=120)
  subprocess.run([str(executable)],check=True,timeout=15)
finally:
 server.shutdown()
 server.server_close()
