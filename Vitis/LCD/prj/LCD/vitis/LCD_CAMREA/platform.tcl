# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct D:\FPGA\Vitis\LCD\prj\LCD\vitis\LCD_CAMREA\platform.tcl
# 
# OR launch xsct and run below command.
# source D:\FPGA\Vitis\LCD\prj\LCD\vitis\LCD_CAMREA\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {LCD_CAMREA}\
-hw {D:\FPGA\Vitis\LCD\prj\LCD\vitis\system_wrapper.xsa}\
-proc {ps7_cortexa9_0} -os {standalone} -fsbl-target {psu_cortexa53_0} -out {D:/FPGA/Vitis/LCD/prj/LCD/vitis}

platform write
platform generate -domains 
platform active {LCD_CAMREA}
platform config -updatehw {D:/FPGA/Vitis/LCD/prj/LCD/vitis/system_wrapper.xsa}
catch {platform remove LCD_CAMREA}
