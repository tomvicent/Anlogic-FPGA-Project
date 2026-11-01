# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct D:\FPGA\ZYNQ\camera\prj\camera\vits\system_wrapper\platform.tcl
# 
# OR launch xsct and run below command.
# source D:\FPGA\ZYNQ\camera\prj\camera\vits\system_wrapper\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {system_wrapper}\
-hw {D:\FPGA\ZYNQ\camera\prj\camera\vits\system_wrapper.xsa}\
-fsbl-target {psu_cortexa53_0} -out {D:/FPGA/ZYNQ/camera/prj/camera/vits}

platform write
domain create -name {standalone_ps7_cortexa9_0} -display-name {standalone_ps7_cortexa9_0} -os {standalone} -proc {ps7_cortexa9_0} -runtime {cpp} -arch {32-bit} -support-app {empty_application}
platform generate -domains 
platform active {system_wrapper}
domain active {zynq_fsbl}
domain active {standalone_ps7_cortexa9_0}
platform generate -quick
platform generate
platform active {system_wrapper}
platform config -updatehw {D:/FPGA/ZYNQ/camera/prj/camera/vits/system_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/FPGA/ZYNQ/camera/prj/camera/vits/system_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/FPGA/ZYNQ/camera/prj/camera/vits/system_wrapper.xsa}
bsp reload
bsp reload
domain active {zynq_fsbl}
bsp reload
bsp reload
platform config -updatehw {D:/FPGA/ZYNQ/camera/prj/camera/vits/system_wrapper.xsa}
domain active {zynq_fsbl}
bsp reload
bsp reload
bsp config stdin "ps7_uart_0"
bsp config stdout "ps7_uart_0"
bsp write
bsp reload
catch {bsp regenerate}
platform generate -domains zynq_fsbl 
platform clean
platform generate
platform config -updatehw {D:/FPGA/ZYNQ/camera/prj/camera/vits/system_wrapper.xsa}
domain active {standalone_ps7_cortexa9_0}
bsp reload
domain active {zynq_fsbl}
bsp reload
domain active {standalone_ps7_cortexa9_0}
bsp config stdin "ps7_uart_0"
bsp config stdout "ps7_uart_0"
bsp write
bsp reload
catch {bsp regenerate}
bsp write
platform generate -domains standalone_ps7_cortexa9_0 
