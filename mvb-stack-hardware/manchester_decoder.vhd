-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity manchester_decoder is
    Port ( clk_xx : in  				std_logic;								-- 16x clock input for clock recovery and oversampling
			  rst : in 						std_logic;
			  rdn : in 						std_logic;								-- control signal initiates read operation
           manchester_in : in  		std_logic;								-- incoming serial manchester-coded data
           decoded_out : out  		unsigned(7 downto 0);				-- outgoing data word
			  data_ready : out 			std_logic;								-- indicates that the decoded_out data is ready
			  decode_error : out			std_logic								-- an error has occured in the decode process (e. g. there was no edge mid-bit)
			  );								
end manchester_decoder;

architecture Behavioral of manchester_decoder is

constant MVB_WORD_WIDTH : integer := 16;								-- MVB data word width is per industry standard 16 bits
constant OVERSAMPLING_FACTOR : integer := 16;						-- oversampling factor
constant SAMPLING_COUNTER_WIDTH : integer := 4;						-- width of the counter, based on which the sample enable signal is generated log2(OS_FACTOR)


---------------------------------------------------------------
---------------------- INTERNAL SIGNALS -----------------------
---------------------------------------------------------------

-- internal shift register for decoded input, value of current decoded bit
signal man_data_in_shr : std_logic_vector(7 downto 0);
signal current_bit_decoded : std_logic;

-- register for edge direction detection
signal input_edge_register : std_logic_vector(1 downto 0);

-- counter for sampling at 25% clk and 75% clk and sample enable signal
signal fourth_counter : unsigned(SAMPLING_COUNTER_WIDTH-1 downto 0);
signal fourth_counter_at_edge : unsigned(SAMPLING_COUNTER_WIDTH-1 downto 0) := to_unsigned(2**SAMPLING_COUNTER_WIDTH - 1, SAMPLING_COUNTER_WIDTH);		-- register to save counter value at edge for sync
signal sample_manchester_input : std_logic;
		--variable sample_at_25 : boolean;
		--variable sample_at_75 : boolean;
signal sample_at_25 : std_logic := '0';
signal sample_at_75 : std_logic := '1';

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin
-- get input bit into shift register
process(rst, sample_manchester_input)
begin
	if(rst = '1') then
		input_edge_register <= "00";
	elsif(sample_manchester_input = '1') then
		input_edge_register <= (input_edge_register(0) & manchester_in);
	else
	end if;
end process;

-- create counter, based on which sampling times can be determined,
-- 	save currently decoded bit value when the clock cycle comes to an end (LSB FIRST)
process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if(rst = '1') then
			fourth_counter <= to_unsigned(0, SAMPLING_COUNTER_WIDTH);
			man_data_in_shr(7 downto 0) <= "00000000";
		elsif(fourth_counter = fourth_counter_at_edge) then
			fourth_counter <= to_unsigned(0, SAMPLING_COUNTER_WIDTH);
			man_data_in_shr(7 downto 0) <= (current_bit_decoded & man_data_in_shr(7 downto 1));
		else
			fourth_counter <= fourth_counter + 1;
		end if;
	end if;	
end process;

-- get edge direction of current bit, save value according to the manchester coding standard
-- save the value of the sampling counter for synchronization purposes
p_DETECT_EDGE : process (input_edge_register)
begin
	case input_edge_register is
		when "10" =>
			current_bit_decoded <= '1';
		when "01" =>
			current_bit_decoded <= '0';
		when others =>
	end case;
	if((fourth_counter > to_unsigned(OVERSAMPLING_FACTOR/4, SAMPLING_COUNTER_WIDTH)) and (fourth_counter < to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH))) then
		fourth_counter_at_edge <= fourth_counter;
	end if;
end process p_DETECT_EDGE;


-- sample value at clk3 and clk11 (at 25% and 75%)
		--sample_at_25 := (fourth_counter = to_unsigned(OVERSAMPLING_FACTOR/4, SAMPLING_COUNTER_WIDTH));
		--sample_at_75 := (fourth_counter = to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH));
sample_at_25 <= '1' when (fourth_counter = to_unsigned(OVERSAMPLING_FACTOR/4, SAMPLING_COUNTER_WIDTH)) else '0';
sample_at_75 <= '1' when (fourth_counter = to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH)) else '0';
sample_manchester_input <= '1' when (sample_at_25 = '1') or (sample_at_75 = '1') else '0';

end Behavioral;

