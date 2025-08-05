/*
 * - 2개의 마스터(EEPROM, OLED)가 하나의 I2C 버스를 사용하도록 중재
 * - 우선순위 EEPROM > OLED
 */

module i2c_arbiter (clk, reset, eeprom_req, oled_req, eeprom_grant, oled_grant, master_sel);
    input clk, reset;
    input eeprom_req, oled_req;
    output reg eeprom_grant, oled_grant;
    output reg [1:0] master_sel;


    // master_sel 이자 state
    localparam IDLE   = 2'b00; 
    localparam EEPROM = 2'b01; // EEPROM 사용중
    localparam OLED   = 2'b10; // OLED 사용중

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            eeprom_grant <= 1'b0;
            oled_grant   <= 1'b0;
            master_sel <= IDLE;
        end
        else begin
            case (master_sel)
                IDLE: begin // 버스 빈 상태
                    if (eeprom_req) begin // eeprom 우선
                        eeprom_grant <= 1'b1;
                        oled_grant   <= 1'b0;
                        master_sel <= EEPROM;
                    end 
                    else if (oled_req) begin
                        eeprom_grant <= 1'b0;
                        oled_grant   <= 1'b1;
                        master_sel <= OLED;
                    end
                end

                EEPROM: begin
                    if (!eeprom_req) begin // 요청 그만하면
                        eeprom_grant <= 1'b0; 
                        master_sel <= IDLE;  
                    end
                end

                OLED: begin
                    if (!oled_req) begin // 요청 그만하면
                        oled_grant   <= 1'b0; 
                        master_sel <= IDLE;   
                    end
                end

                default: begin
                    eeprom_grant <= 1'b0;
                    oled_grant   <= 1'b0;
                    master_sel <= IDLE;
                end
            endcase
        end
    end


    /////// simulation debugging 용 ////////////
    reg [39:0] state;
    always @(*) begin
        case (master_sel)
            IDLE :      state = "IDLE ";
            EEPROM:    state = "EPROM";
            OLED:    state = "OLED ";
            default: state = "UNDEF";
        endcase
    end


endmodule