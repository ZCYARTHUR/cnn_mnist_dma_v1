"""Run from any folder; requires a C++ toolchain and Verilator (--binary)."""
import argparse,os,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--lanes',nargs='+',type=int,default=[4,8,16])
p.add_argument('--vectors',default='trained')
p.add_argument('--build-dir',default='build/verilator')
args=p.parse_args()
root=Path(__file__).resolve().parents[1]
import json
vectors=(root/args.vectors).resolve()
frames=json.loads((vectors/'metadata.json').read_text())['frames']
if frames>64:raise SystemExit('TB supports <=64 frames; export a smaller test subset')
exe=os.environ.get('VERILATOR') or shutil.which('verilator') or shutil.which('verilator-cli')
if not exe:raise SystemExit('Install Verilator and a C++ compiler; or use scripts/run_xsim.bat on Windows')
build=(root/args.build_dir).resolve();build.mkdir(parents=True,exist_ok=True)
rtl=sorted(map(str,(root/'rtl').glob('*.sv')))
for lane in args.lanes:
 if lane not in (4,8,16):raise SystemExit('LANES must be 4,8,16')
 d=build/f'l{lane}';d.mkdir(exist_ok=True)
 cmd=[exe,'--binary','--timing','--assert','--top-module','tb_cnn',f'-GLANES={lane}',
      '--Mdir',str(d),'-o','sim_cnn',*rtl,str(root/'sim/tb_cnn.sv')]
 with (d/'compile.log').open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
 result=subprocess.run([str(d/'sim_cnn'),f'+VECTORS={vectors}',f'+FRAMES={frames}'],text=True,capture_output=True)
 (d/'simulation.log').write_text(result.stdout+result.stderr)
 print(result.stdout);result.check_returncode()
d=build/'quant';d.mkdir(exist_ok=True)
with (d/'compile.log').open('w') as log:
 subprocess.run([exe,'--binary','--timing','--top-module','tb_requantize','--Mdir',str(d),'-o','sim_quant',
 str(root/'rtl/requantize.sv'),str(root/'sim/tb_requantize.sv')],stdout=log,stderr=subprocess.STDOUT,check=True)
r=subprocess.run([str(d/'sim_quant')],text=True,capture_output=True)
(d/'simulation.log').write_text(r.stdout+r.stderr);print(r.stdout);r.check_returncode()
