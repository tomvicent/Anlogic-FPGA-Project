# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct D:\FPGA\Vitis\LCD\prj\LCD\vitis\system_wrapper\platform.tcl
# 
# OR launch xsct and run below command.
# source D:\FPGA\Vitis\LCD\prj\LCD\vitis\system_wrapper\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {system_wrapper}\
-hw {D:\FPGA\Vitis\LCD\prj\LCD\vitis\system_wrapper.xsa}\
-fsbl-target {psu_cortexa53_0} -out {D:/FPGA/Vitis/LCD/prj/LCD/vitis}

platform write
domain create -name {standalone_ps7_cortexa9_0} -display-name {standalone_ps7_cortexa9_0} -os {standalone} -proc {ps7_cortexa9_0} -runtime {cpp} -arch {32-bit} -support-app {empty_application}
platform generate -domains 
platform active {system_wrapper}
domain active {zynq_fsbl}
domain active {standalone_ps7_cortexa9_0}
platform generate -quick
platform generate
bsp reload
domain active {zynq_fsbl}
bsp reload
bsp reload
bsp reload
platform active {system_wrapper}
platform generate -domains 
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform generate -domains 
platform clean
platform generate
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform clean
platform generate
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform clean
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
domain active {zynq_fsbl}
bsp reload
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/system_wrapper.xsa}
platform active {system_wrapper}
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform active {system_wrapper}
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
platform generate
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
catch {platform remove system_wrapper}
