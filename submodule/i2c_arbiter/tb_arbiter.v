`timescale 1ns / 1ps
module tb_arbiter();
    reg clk, reset;
    reg eeprom_req, oled_req;
    wire eeprom_grant, oled_grant;
    wire [1:0] master_sel;

    i2c_arbiter  U_arbiter(.clk(clk), .reset(reset), .eeprom_req(eeprom_req), .oled_req(oled_req),
                       .eeprom_grant(eeprom_grant), .oled_grant(oled_grant), .master_sel(master_sel));
    
    always #5 clk=~clk;
	initial begin
		   	clk=1'b0; reset=1'b0; eeprom_req=1'b0; oled_req=1'b0;
		#15   reset=1'b1; 
        #200  reset=1'b0; 
		#300	eeprom_req=1'b0; oled_req=1'b1;
		#300	eeprom_req=1'b1; oled_req=1'b1;
		#300	eeprom_req=1'b1; oled_req=1'b0;
		#300	eeprom_req=1'b0; oled_req=1'b0;
		#150   reset=1'b1; 
        #150   reset=1'b0; 
		#300	eeprom_req=1'b1; oled_req=1'b1;
		#300	eeprom_req=1'b1; oled_req=1'b0;
		#300	eeprom_req=1'b0; oled_req=1'b0;
		#300	eeprom_req=1'b0; oled_req=1'b1;
		#300	$finish;
	end

endmodule
