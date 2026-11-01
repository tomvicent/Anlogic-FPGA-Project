# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct D:\FPGA\Vitis\UDP\prj\udp_camera\vitis\system_wrapper\platform.tcl
# 
# OR launch xsct and run below command.
# source D:\FPGA\Vitis\UDP\prj\udp_camera\vitis\system_wrapper\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {system_wrapper}\
-hw {D:\FPGA\Vitis\UDP\prj\udp_camera\vitis\system_wrapper.xsa}\
-fsbl-target {psu_cortexa53_0} -out {D:/FPGA/Vitis/UDP/prj/udp_camera/vitis}

platform write
domain create -name {standalone_ps7_cortexa9_0} -display-name {standalone_ps7_cortexa9_0} -os {standalone} -proc {ps7_cortexa9_0} -runtime {cpp} -arch {32-bit} -support-app {lwip_udp_perf_server}
platform generate -domains 
platform active {system_wrapper}
domain active {zynq_fsbl}
domain active {standalone_ps7_cortexa9_0}
platform generate -quick
platform active {system_wrapper}
bsp reload
bsp reload
platform generate
platform clean
platform generate
platform clean
platform generate
platform config -updatehw {D:/FPGA/Vitis/UDP/prj/udp_camera/vitis/system_wrapper.xsa}
platform clean
platform generate
