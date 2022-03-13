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

constant v_MVB_WORD_WIDTH : integer := 16;								-- MVB data word width is per industry standard 16 bits
constant v_OVERSAMPLING_FACTOR : integer := 16;						-- oversampling factor
constant v_SAMPLING_COUNTER_WIDTH : integer := 4;						-- width of the counter, based on which the sample enable signal is generated log2(OS_FACTOR)

-- state machine constants:
constant v_IDLE : std_logic_vector(2 downto 0) := "000";
constant v_START_BIT : std_logic_vector(2 downto 0) := "001";
constant v_START_DELIMITER : std_logic_vector(2 downto 0) := "010";
constant v_RECEIVE_MASTER : std_logic_vector(2 downto 0) := "011";
constant v_RECEIVE_SLAVE : std_logic_vector(2 downto 0) := "100";
constant v_RECEIVE_CRC : std_logic_vector(2 downto 0) := "101";
constant v_END_DELIMITER : std_logic_vector(2 downto 0) := "110";

-- constants for delimiter detection (start bit not included)
constant v_MASTER_DELIMITER : std_logic_vector(15 downto 0) := "1100011100010101";
constant v_SLAVE_DELIMITER : std_logic_vector(15 downto 0) := "1010100011100011";


---------------------------------------------------------------
---------------------- INTERNAL SIGNALS -----------------------
---------------------------------------------------------------

-- internal shift register for decoded input, value of current decoded bit
signal r_MAN_DATA_IN_SHIFT : std_logic_vector(7 downto 0);							-- shift register storing serial input data, active during RECEIVE_MASTER or RECEIVE_SLAVE
signal r_CURRENT_BIT_DECODED : std_logic;													-- non-manchester value of the latest manchester bit

-- registers and signals for bit time measurement
signal r_INPUT_BIT_TIME_SHIFT : std_logic_vector(1 downto 0);						-- fast-changing shift register for low delay edge detection in manchester_in
signal r_SAMPLING_COUNTER_AT_HALF_BIT : unsigned(v_SAMPLING_COUNTER_WIDTH-1 downto 0) := to_unsigned(2**v_SAMPLING_COUNTER_WIDTH - 1, v_SAMPLING_COUNTER_WIDTH);		-- register to save counter value at edge for BT measurement
signal s_IN_BIT_MIDDLE : std_logic := '0';												-- indicator signal that the transmission is between 25% BT and 75% BT, so an edge should be expected
signal s_AT_EDGE : std_logic := '0';														-- indicator signal that an edge has been detected on r_INPUT_BIT_TIME_SHIFT

-- registers and signals for determining current bit value
signal r_INPUT_EDGE_SHIFT : std_logic_vector(1 downto 0);							-- stores measured values at 25% BT and 75% BT
signal r_SAMPLING_COUNTER : unsigned(v_SAMPLING_COUNTER_WIDTH-1 downto 0);		-- counter that schedules data measurements at 25% and 75% BT
signal s_SAMPLE_MANCHESTER_INPUT : std_logic;											-- data sampling indicator
signal s_SAMPLE_AT_25 : std_logic := '0';
signal s_SAMPLE_AT_75 : std_logic := '1';

-- signals for receiving a delimiter
signal r_START_DELIMITER_IN : std_logic_vector(15 downto 0) := "0000000000000000";	-- shift register receiving the start delimiter sequence at double bit rate
signal r_START_DELIMITER_COUNTER : unsigned(4 downto 0) := to_unsigned(0, 5);			-- counter that measures how many bits of the start delimiter have been received (counts to 16)
signal s_START_DELIMITER_VALUE_CHECK : std_logic_vector(1 downto 0) := "00";			-- wire to check validity and value of the delimiter		

-- state machine signals:
signal r_STATE : std_logic_vector(2 downto 0) := "000";
signal s_AT_RISING_EDGE : std_logic := '0';												-- 1 if a rising edge is detected (as close to the rising edge as possible)
signal r_START_BIT_BIT_TIME : unsigned(v_SAMPLING_COUNTER_WIDTH-1 downto 0) := to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);		-- counter to measure the half bit time of the start bit
signal s_DECODE_MANCHESTER : std_logic := '0';											-- only decode manchester signal if either data or CRC is being received

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin

--_____________________________DECODE MANCHESTER CODE_____________________________--
s_DECODE_MANCHESTER <= '1' when ((r_STATE = v_RECEIVE_MASTER) or (r_STATE = v_RECEIVE_SLAVE) or (r_STATE = r_RECEIVE_CRC)) else '0';

-- get input bit into shift register on every sample enable signal (bit value detection)
p_DETECT_IN_BIT_STATE_CHANGE : process(clk_xx)
begin
	if(rising_edge(clk_xx) and (s_DECODE_MANCHESTER = '1')) then
		if(rst = '1') then
			r_INPUT_EDGE_SHIFT <= "00";
		elsif(s_SAMPLE_MANCHESTER_INPUT = '1') then
			r_INPUT_EDGE_SHIFT <= (r_INPUT_EDGE_SHIFT(0) & manchester_in);
		else
		end if;
	else
	end if;
end process p_DETECT_IN_BIT_STATE_CHANGE;

-- detect edge as close to the edge as possible (half-bit-time detection)
s_IN_BIT_MIDDLE <= '1' when ((r_SAMPLING_COUNTER > to_unsigned(v_OVERSAMPLING_FACTOR/4, v_SAMPLING_COUNTER_WIDTH)) and (r_SAMPLING_COUNTER < to_unsigned(v_OVERSAMPLING_FACTOR*3/4, v_SAMPLING_COUNTER_WIDTH))) else '0';
s_AT_EDGE <= '1' when ((r_INPUT_BIT_TIME_SHIFT = "10") or (r_INPUT_BIT_TIME_SHIFT = "01")) else '0';

p_DETECT_BIT_TIME : process(clk_xx)
begin
	if(rising_edge(clk_xx) and (s_DECODE_MANCHESTER = '1')) then
		if(rst = '1') then
			r_INPUT_BIT_TIME_SHIFT <= "00";
		else
			r_INPUT_BIT_TIME_SHIFT <= (r_INPUT_BIT_TIME_SHIFT(0) & manchester_in);
		end if;
	end if;
	-- detect edge in the middle of bit time
	if((s_IN_BIT_MIDDLE = '1') and (s_AT_EDGE = '1')) then
		r_SAMPLING_COUNTER_AT_HALF_BIT <= r_SAMPLING_COUNTER;
	end if;
end process p_DETECT_BIT_TIME;

-- create counter, based on which sampling times can be determined,
-- 	save currently decoded bit value when the clock cycle comes to an end (LSB FIRST)
p_SAMPLING_COUNTER : process(clk_xx)
begin
	if(rising_edge(clk_xx) and (s_DECODE_MANCHESTER = '1')) then
		if(rst = '1') then
			r_SAMPLING_COUNTER <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
			r_MAN_DATA_IN_SHIFT(7 downto 0) <= "00000000";
		-- reset on the measured bit-width (-5 is needed, because the value read is delayed by two cycles, and the delay is doubled)
		elsif(r_SAMPLING_COUNTER = (2*r_SAMPLING_COUNTER_AT_HALF_BIT-5)) then
			r_SAMPLING_COUNTER <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
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
s_SAMPLE_AT_25 <= '1' when (r_SAMPLING_COUNTER = to_unsigned(v_OVERSAMPLING_FACTOR/4, v_SAMPLING_COUNTER_WIDTH)) else '0';
s_SAMPLE_AT_75 <= '1' when (r_SAMPLING_COUNTER = to_unsigned(v_OVERSAMPLING_FACTOR*3/4, v_SAMPLING_COUNTER_WIDTH)) else '0';
s_SAMPLE_MANCHESTER_INPUT <= '1' when (s_SAMPLE_AT_25 = '1') or (s_SAMPLE_AT_75 = '1') else '0';

--_____________________________RECEIVE START DELIMITER_____________________________--
-- In the start delimiter state, the input sequence will be sampled at double bitrate, because
--		manchester coding is ignored, and the delimiter is treated as a single 16 bit sequence.
-- The validity of the received sequence is checked after the full transmission, by the state machine.

p_RECEIVE_START_DELIMITER : process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if((r_STATE = v_START_DELIMITER) and ((s_SAMPLE_AT_25 = '1') or (s_SAMPLE_AT_75 = '1'))) then
			r_START_DELIMITER_IN <= (r_START_DELIMITER_IN(14 downto 0) & manchester_in);
			r_START_DELIMITER_COUNTER <= r_START_DELIMITER_COUNTER + 1;
		elsif(r_STATE /= v_START_DELIMITER) then
			r_START_DELIMITER_IN <= "0000000000000000";
			r_START_DELIMITER_COUNTER <= to_unsigned(0, 5);
		else
		end if;
	else
	end if;
end process p_RECEIVE_START_DELIMITER;

-- is the delimiter currently stored in the shift register valid? is it a master or a slave frame?
p_START_DELIMITER_VALUE_CHECK : process(r_START_DELIMITER_IN)
begin
	case r_START_DELIMITER_IN is
		when v_MASTER_DELIMITER 	=> 	s_START_DELIMITER_VALUE_CHECK <= "01";
		when v_SLAVE_DELIMITER  	=> 	s_START_DELIMITER_VALUE_CHECK <= "10";
		when others 					=> 	s_START_DELIMITER_VALUE_CHECK <= "00";
	end case;
end process p_START_DELIMITER_VALUE_CHECK;


--_____________________________TRANSMISSION STATE MACHINE_____________________________--
s_AT_RISING_EDGE <= '1' when (r_INPUT_BIT_TIME_SHIFT = "01") else '0';
s_AT_FALLING_EDGE <= '1' when (r_INPUT_BIT_TIME_SHIFT = "10") else '0';

-- how many cycles does the start bit last?
p_MEASURE_INITIAL_BIT_TIME : process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if(rst = '1') then
			r_START_BIT_BIT_TIME <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
		elsif(r_STATE = v_START_BIT) then
			r_START_BIT_BIT_TIME <= r_START_BIT_BIT_TIME + 1;
		else
		end if;
	else
	end if;
end process p_MEASURE_INITIAL_BIT_TIME;


p_TRANSMISSION_STATE_MACHINE : process(clk_xx)
begin
	if(rising_edge(clk_xx)) then
		if(rst = '1') then
			r_STATE <= v_IDLE;
		-- idle --> next rising edge is a start bit
		elsif((r_STATE = v_IDLE) and (s_AT_RISING_EDGE = '1')) then
			r_STATE <= v_START_BIT;
		-- start bit --> next rising edge is a start delimiter
		elsif((r_STATE = v_START_BIT) and (s_AT_RISING_EDGE = '1')) then
			r_STATE <= v_START_DELIMITER;
		-- if delimiter is valid, set its type, if it is not, return to idle
		elsif((r_STATE = v_START_DELIMITER) and (r_START_DELIMITER_COUNTER = to_unsigned(16, 5))) then
			case s_START_DELIMITER_VALUE_CHECK is
				when "01"	=>		r_STATE <= v_RECEIVE_MASTER;
				when "10"	=>		r_STATE <= v_RECEIVE_SLAVE;
				when others =>		r_STATE <= v_IDLE;
			end case;
		else
			r_STATE 	<= v_IDLE;
		end if;
	else
	end if;
end process p_TRANSMISSION_STATE_MACHINE;











end Behavioral;

