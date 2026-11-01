module i2c_dri 
    #(  
        parameter   SLAVE_ADDR  = 7'b1010000   ,  //EEPROM 从机地址        
        parameter   CLK_FREQ    = 26'd50_000_000, //模块输入的时钟频率
        parameter   I2C_FREQ    = 18'd250_000     //IIC_SCL 的时钟频率
    )
    (
        input           clk;
        input           rst_n;
        //i2c interface
        input                i2c_exec   ,  //I2C触发执行信号
        input                bit_ctrl   ,  //字地址位控制(16b/8b)
        input                i2c_rh_wl  ,  //I2C读写控制信号
        input        [15:0]  i2c_addr   ,  //I2C器件内地址
        input        [ 7:0]  i2c_data_w ,  //I2C要写的数据
        output  reg  [ 7:0]  i2c_data_r ,  //I2C读出的数据
        output  reg          i2c_done   ,  //I2C一次操作完成     
        output  reg          i2c_ack    ,  //I2C应答标志 0:应答 1:未应答
        output  reg          scl        ,  //I2C的SCL时钟信号
        inout                sda        ,  //I2C的SDA信号

        //user interface
        output  reg          dri_clk       //驱动I2C操作的驱动时钟
    );

//localparam define 
localparam  st_idle     = 8'b0000_0001; //空闲状态
localparam  st_sladdr   = 8'b0000_0010; //发送器件地址(slave address)
localparam  st_addr16   = 8'b0000_0100; //发送16位字地址
localparam  st_addr8    = 8'b0000_1000; //发送8位字地址
localparam  st_data_wr  = 8'b0001_0000; //写数据(8 bit)
localparam  st_addr_rd  = 8'b0010_0000; //发送器件地址读
localparam  st_data_rd  = 8'b0100_0000; //读数据(8 bit)
localparam  st_stop     = 8'b1000_0000; //结束I2C操作

//reg define
reg            sda_dir   ; //I2C数据(SDA)方向控制
reg            sda_out   ; //SDA输出信号
reg            st_done   ; //状态结束
reg            wr_flag   ; //写标志
reg    [ 6:0]   cnt       ; //计数器
reg    [ 7:0]   cur_state ; //状态机当前状态
reg    [ 7:0]   next_state; //状态机下一状态
reg    [15:0]   addr_t    ; //地址
reg    [ 7:0]   data_r    ; //读取的数据
reg    [ 7:0]   data_wr_t ; //I2C需写的数据的临时寄存
reg    [ 9:0]   clk_cnt   ; //分频时钟计数

//wire define
wire           sda_in     ; //SDA输入信号
wire   [8:0]   clk_divide ; //模块驱动时钟的分频系数

//SDA控制 
assign  sda        = sda_dir ?  sda_out : 1'bz   ;  //SDA数据输出或高阻
assign  sda_in     = sda                         ;  //SDA数据输入 

assign  clk_divide = (CLK_FREQ/I2C_FREQ) >> 2'd2 ;  //模块驱动时钟的分频系数,相当于除于4，最后等于50

//生成I2C的SCL的四倍频率的驱动时钟用于驱动i2c的操作
/*需要四倍频的原因是因为，需要四个动作，上升，保持，采样，下降，这个是25 *2ns 就翻转一次的方波*/
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dri_clk <=  1'b0;
        clk_cnt <= 10'd0;
    end
    else if(clk_cnt == (clk_divide[8:1] - 10'd1)) begin
        clk_cnt <= 10'd0;
        dri_clk <= ~dri_clk;
    end
    else
        clk_cnt <= clk_cnt + 10'b1;
end

/*如果reset就进入空闲状态，要么就在下一状态，也是类似于初始化了*/
always @(posedge dri_clk or negedge rst_n) begin 
    if(!rst_n)
        cur_state <= st_idle;
    else
        cur_state <= next_state;
end

//组合逻辑判断状态转移条件,这个是IIC的各种状态的跳变
always @(*) begin
    next_state = st_idle;
    case (cur_state)
        st_idle: begin                  //空闲状态
            if(i2c_exec) begin
                next_state = st_sladdr;
            end
            else
                next_state = st_idle;
        end

        st_sladdr: begin
            if(st_done) begin
                if(bit_ctrl)            //判断是16 位还是8位字地址
                    next_state = st_addr16;
                else
                    next_state = st_addr8 ;
            end
            else
                next_state = st_sladdr; //发送器件地址
        end

        st_addr16: begin                    //写 16 位字地址
            if(st_done) begin
                next_state = st_addr8;
            end
            else begin
                next_state = st_addr16;
            end
        end

        st_addr8: begin                     //8 位字地址
            if(st_done) begin
                if(wr_flag==1'b0)           //读写判断，0是写地址，1是读地址
                    next_state = st_data_wr;
                else
                    next_state = st_addr_rd;
                end
            else begin
                    next_state = st_addr8;
                end
        end

        st_data_wr: begin                   //写数据(8 bit)
            if(st_done)
                next_state = st_stop;
            else
                next_state = st_data_wr;
        end

        st_addr_rd: begin                   //写地址以进行读数据
            if(st_done) begin
                next_state = st_data_rd;
            end
            else begin
                next_state = st_addr_rd;
            end
        end

        st_data_rd: begin                   //读取数据(8 bit)
            if(st_done)
                next_state = st_stop;
            else
                next_state = st_data_rd;
        end


        st_stop: begin                      //结束 I2C 操作
            if(st_done)
                next_state = st_idle;
            else
                next_state = st_stop ;
        end

        default: next_state= st_idle;
    endcase
end


endmodule