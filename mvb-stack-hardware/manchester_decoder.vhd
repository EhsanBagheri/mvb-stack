-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity e_MANCHESTER_DECODER is
    Port ( clk_xx : in  				std_logic;								-- 16x clock input for clock recovery and oversampling
			  rst : in 						std_logic;
			  rdn : in 						std_logic;								-- control signal initiates read operation
           manchester_in : in  		std_logic;								-- incoming serial manchester-coded data
           decoded_out : out  		unsigned(7 downto 0);				-- outgoing data word
			  data_ready : out 			std_logic;								-- indicates that the decoded_out data is ready
			  decode_error : out			std_logic								-- an error has occured in the decode process (e. g. there was no edge mid-bit)
			  );								
end e_MANCHESTER_DECODER;

architecture Behavioral of e_MANCHESTER_DECODER is

constant MVB_WORD_WIDTH : integer := 16;								-- MVB data word width is per industry standard 16 bits
constant OVERSAMPLING_FACTOR : integer := 16;						-- oversampling factor
constant SAMPLING_COUNTER_WIDTH : integer := 4;						-- width of the counter, based on which the sample enable signal is generated log2(OS_FACTOR)


---------------------------------------------------------------
---------------------- INTERNAL SIGNALS -----------------------
---------------------------------------------------------------

-- internal shift register for decoded input, value of current decoded bit
signal r_MAN_DATA_IN_SHIFT : std_logic_vector(7 downto 0);
signal r_CURRENT_BIT_DECODED : std_logic;

-- registers and signals for bit time measurement
signal r_INPUT_BIT_TIME_SHIFT : std_logic_vector(1 downto 0);
signal r_SAMPLING_COUNTER_AT_HALF_BIT : unsigned(SAMPLING_COUNTER_WIDTH-1 downto 0) := to_unsigned(2**SAMPLING_COUNTER_WIDTH - 1, SAMPLING_COUNTER_WIDTH);		-- register to save counter value at edge for sync
signal s_IN_BIT_MIDDLE : std_logic := '0';
signal s_AT_EDGE : std_logic := '0';

-- registers and signals for determining current bit value
signal r_INPUT_EDGE_SHIFT : std_logic_vector(1 downto 0);
signal r_SAMPLING_COUNTER : unsigned(SAMPLING_COUNTER_WIDTH-1 downto 0);
signal s_SAMPLE_MANCHESTER_INPUT : std_logic;
signal s_SAMPLE_AT_25 : std_logic := '0';
signal s_SAMPLE_AT_75 : std_logic := '1';

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin
-- get input bit into shift register on every sample enable signal (bit value detection)
p_DETECT_IN_BIT_STATE_CHANGE : process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if(rst = '1') then
			r_INPUT_EDGE_SHIFT <= "00";
		elsif(s_SAMPLE_MANCHESTER_INPUT = '1') then
			r_INPUT_EDGE_SHIFT <= (r_INPUT_EDGE_SHIFT(0) & manchester_in);
		else
		end if;
	else
	end if;
end process p_DETECT_IN_BIT_STATE_CHANGE;

-- detect edge as close to the edge as possible, to measure half bit-time
s_IN_BIT_MIDDLE <= '1' when ((r_SAMPLING_COUNTER > to_unsigned(OVERSAMPLING_FACTOR/4, SAMPLING_COUNTER_WIDTH)) and (r_SAMPLING_COUNTER < to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH))) else '0';
s_AT_EDGE <= '1' when ((r_INPUT_BIT_TIME_SHIFT = "10") or (r_INPUT_BIT_TIME_SHIFT = "01")) else '0';

p_DETECT_BIT_TIME : process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if(rst = '1') then
			r_INPUT_BIT_TIME_SHIFT <= "00";
		else
			r_INPUT_BIT_TIME_SHIFT <= (r_INPUT_BIT_TIME_SHIFT(0) & manchester_in);
		end if;
	end if;
	if((s_IN_BIT_MIDDLE = '1') and (s_AT_EDGE = '1')) then
		r_SAMPLING_COUNTER_AT_HALF_BIT <= r_SAMPLING_COUNTER;
	end if;
end process p_DETECT_BIT_TIME;

-- create counter, based on which sampling times can be determined,
-- 	save currently decoded bit value when the clock cycle comes to an end (LSB FIRST)
p_SAMPLING_COUNTER : process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if(rst = '1') then
			r_SAMPLING_COUNTER <= to_unsigned(0, SAMPLING_COUNTER_WIDTH);
			r_MAN_DATA_IN_SHIFT(7 downto 0) <= "00000000";
		-- reset on the measured bit-width (-5 is needed, because the value read is delayed by two cycles, and the delay is doubled)
		elsif(r_SAMPLING_COUNTER = (2*r_SAMPLING_COUNTER_AT_HALF_BIT-5)) then
			r_SAMPLING_COUNTER <= to_unsigned(0, SAMPLING_COUNTER_WIDTH);
			r_MAN_DATA_IN_SHIFT(7 downto 0) <= (r_CURRENT_BIT_DECODED & r_MAN_DATA_IN_SHIFT(7 downto 1));
		else
			r_SAMPLING_COUNTER <= r_SAMPLING_COUNTER + 1;
		end if;
	end if;	
end process p_SAMPLING_COUNTER;

-- get edge direction of current bit, save value according to the manchester coding standard
-- save the value of the sampling counter for synchronization purposes
p_DECODE_BIT_VALUE : process (r_INPUT_EDGE_SHIFT)
begin
	case r_INPUT_EDGE_SHIFT is
		when "10" =>
			r_CURRENT_BIT_DECODED <= '1';
		when "01" =>
			r_CURRENT_BIT_DECODED <= '0';
		when others =>
	end case;
end process p_DECODE_BIT_VALUE;


-- sample value at clk3 and clk11 (at 25% and 75%)
s_SAMPLE_AT_25 <= '1' when (r_SAMPLING_COUNTER = to_unsigned(OVERSAMPLING_FACTOR/4, SAMPLING_COUNTER_WIDTH)) else '0';
s_SAMPLE_AT_75 <= '1' when (r_SAMPLING_COUNTER = to_unsigned(OVERSAMPLING_FACTOR*3/4, SAMPLING_COUNTER_WIDTH)) else '0';
s_SAMPLE_MANCHESTER_INPUT <= '1' when (s_SAMPLE_AT_25 = '1') or (s_SAMPLE_AT_75 = '1') else '0';

end Behavioral;

