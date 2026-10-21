@echo off
setlocal
rem Run in an AMD/Vivado command prompt, or first call settings64.bat.
rem Usage: scripts\run_xsim.bat 4 trained 16
set CNN_LANES=%~1
if "%CNN_LANES%"=="" set CNN_LANES=4
set CNN_VECTORS=%~2
if "%CNN_VECTORS%"=="" set CNN_VECTORS=trained
set CNN_FRAMES=%~3
if "%CNN_FRAMES%"=="" set CNN_FRAMES=16
pushd "%~dp0.."
set CNN_ROOT=%CD%
if not exist "build\xsim_%CNN_LANES%" mkdir "build\xsim_%CNN_LANES%"
cd "build\xsim_%CNN_LANES%"
type nul > files.prj
for %%f in ("%CNN_ROOT%\rtl\*.sv") do echo sv xil_defaultlib "%%f" >> files.prj
echo sv xil_defaultlib "%CNN_ROOT%\sim\tb_cnn.sv" >> files.prj
echo sv xil_defaultlib "%CNN_ROOT%\sim\tb_requantize.sv" >> files.prj
call xvlog --prj files.prj
if errorlevel 1 goto fail
call xelab xil_defaultlib.tb_cnn -generic_top "LANES=%CNN_LANES%" -s cnn_snapshot
if errorlevel 1 goto fail
call xsim cnn_snapshot -testplusarg "VECTORS=%CNN_ROOT%/%CNN_VECTORS%" -testplusarg "FRAMES=%CNN_FRAMES%" -runall
if errorlevel 1 goto fail
call xelab xil_defaultlib.tb_requantize -s quant_snapshot
if errorlevel 1 goto fail
call xsim quant_snapshot -runall
if errorlevel 1 goto fail
popd
exit /b 0
:fail
echo Simulation failed. Check xvlog.log, xelab.log and xsim.log.
popd
exit /b 1
