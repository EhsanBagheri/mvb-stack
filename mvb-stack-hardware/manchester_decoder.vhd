-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity manchester_decoder is
    Port ( clk_xx : in  std_logic;										-- 16x clock input for clock recovery and oversampling
			  rst : in std_logic;
			  rdn : in std_logic;											-- control signal initiates read operation
           manchester_in : in  std_logic;								-- incoming serial manchester-coded data
           decoded_out : out  unsigned(7 downto 0);				-- outgoing data word
			  data_ready : out std_logic									-- indicates that the decoded_out data is ready
			  );								
end manchester_decoder;

architecture Behavioral of manchester_decoder is

constant MVB_WORD_WIDTH : integer := 16;								-- MVB data word width is per industry standard 16 bits
constant OVERSAMPLING_FACTOR : integer := 16;						-- oversampling factor
constant SAMPLING_COUNTER_WIDTH : integer := 4;						-- width of the counter, based on which the sample enable signal is generated log2(OS_FACTOR)


---------------------------------------------------------------
---------------------- INTERNAL SIGNALS -----------------------
---------------------------------------------------------------

-- internal register for edge detection (cells will be XOR-ed)
signal man_data_in1 : std_logic_vector(1 downto 0);

-- internal 1x clock signal and clock enable
signal clk1x : std_logic;
signal clk1x_en : std_logic;

-- counter for sampling at 25% clk and 75% clk and sample enable signal
signal fourth_counter : unsigned(SAMPLING_COUNTER_WIDTH downto 0);
signal sample_manchester_input : std_logic;

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin

-- create counter based on which sampling times can be determined
process(rst,  clk_xx)
begin
	if(rst = '1') then
		fourth_counter <= to_unsigned(0, SAMPLING_COUNTER_WIDTH);
	else
		fourth_counter <= fourth_counter + 1;
	end if;
		
end process;



-- sample value at clk3 and clk11
sample_manchester_input <= '1' when (fourth_counter = to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH))
	or (fourth_counter = to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH)) else '0';

end Behavioral;

