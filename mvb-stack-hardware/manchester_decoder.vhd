-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity e_MANCHESTER_DECODER is
    Port ( clk 				: 	in  		std_logic;								-- 16x clock input for clock recovery and oversampling
			  rst 				:	in 		std_logic;
			  rdn 				: 	in 		std_logic;								-- control signal initiates read operation
           manchester_in 	: 	in  		std_logic;								-- incoming serial manchester-coded data
           decoded_out 		: 	out  		std_logic_vector(15 downto 0);	-- outgoing data word
			  data_ready 		: 	out 		std_logic;								-- indicates that the decoded_out data is ready
			  decode_error 	: 	out		std_logic								-- an error has occured in the decode process (e. g. there was no edge mid-bit)
			  );								
end e_MANCHESTER_DECODER;

architecture Behavioral of e_MANCHESTER_DECODER is

constant v_MVB_WORD_WIDTH_WIDTH : integer := 4;
constant v_MVB_WORD_WIDTH : integer := 2**v_MVB_WORD_WIDTH_WIDTH;	-- MVB data word width is per industry standard 16 bits, which fits on 4 bits
constant v_SAMPLING_COUNTER_WIDTH : integer := 16;						-- width of the counter, based on which the sample enable signal is generated log2(oversampling)

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
signal r_MAN_DATA_IN_SHIFT : std_logic_vector(15 downto 0);							-- shift register storing serial input data, active during RECEIVE_MASTER or RECEIVE_SLAVE
signal r_CURRENT_BIT_DECODED : std_logic;													-- non-manchester value of the latest manchester bit
signal r_MESSAGE_LENGTH_COUNTER : unsigned(4 downto 0);								-- number of decoded bits in the current message --> state machine can determine when the CRC should be expected
signal s_MESSAGE_WORD_READY : std_logic := '0';											-- 16 bit word has been received on the manchester coded input
signal r_SLAVE_DATA_RECEIVED : std_logic_vector(15 downto 0);						-- register that stores the complete DATA part of a frame (currently 16 bits only)
signal r_WORD_COUNTER : unsigned(4 downto 0);											-- how many 16 bit words need to be read until the transmission is over?

-- registers and signals for bit time measurement
signal r_INPUT_BIT_TIME_SHIFT : std_logic_vector(1 downto 0);						-- fast-changing shift register for low delay edge detection in manchester_in
signal r_SAMPLING_COUNTER_AT_HALF_BIT : unsigned(v_SAMPLING_COUNTER_WIDTH-1 downto 0) := to_unsigned(2**v_SAMPLING_COUNTER_WIDTH - 1, v_SAMPLING_COUNTER_WIDTH);		-- register to save counter value at edge for BT measurement
signal r_NEXT_BIT_TIME : unsigned(v_SAMPLING_COUNTER_WIDTH-1 downto 0);			-- length of the next bit time
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

-- signals for receiving the 8 bit check sequence (CRC)
signal r_CRC_IN : std_logic_vector(7 downto 0) := "00000000";						-- input shift register for the CRC
signal s_CRC_READY : std_logic := '0';														-- '1' when the CRC is completely received

-- signal representing the end of the end delimiter									(end delimiter is: NL symbol for ESD, NL + NH symbols for EMD)
signal s_END_OF_END_DELIMITER : std_logic := '0';										-- 1 when an end delimiter is closed with a falling edge

-- state machine signals:
signal r_STATE : std_logic_vector(2 downto 0) := "000";
signal s_AT_RISING_EDGE : std_logic := '0';												-- 1 if a rising edge is detected (as close to the rising edge as possible)
signal s_AT_FALLING_EDGE : std_logic := '0';												-- 1 if a falling edge is detected (-||-)
signal r_START_BIT_BIT_TIME : unsigned(v_SAMPLING_COUNTER_WIDTH-1 downto 0) := to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);		-- counter to measure the half bit time of the start bit
signal s_DECODE_MANCHESTER : std_logic := '0';											-- only decode manchester signal if either data or CRC is being received

-- registers that carry information across transmissions
signal r_LAST_RECEIVED_MASTER_DATA : std_logic_vector(15 downto 0);				-- stores the data from the last master frame to have been read from the bus
signal r_DEVICE_ADDRESS : std_logic_vector(11 downto 0) := "000000000001";		-- stores this device's MVB bus address, the device responds to master frames containing this address
signal r_WAITING_FOR_SLAVE : std_logic := '0';											-- device has been address and is waiting for the next slave frame
signal r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH : unsigned(4 downto 0);				-- how many times 16 bits is the next slave data going to be? (from F code)

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin

--_____________________________DECODE MANCHESTER CODE_____________________________--
s_DECODE_MANCHESTER <= '1' when ((r_STATE = v_RECEIVE_MASTER) or (r_STATE = v_RECEIVE_SLAVE) or (r_STATE = v_RECEIVE_CRC)) else '0';
s_MESSAGE_WORD_READY <= '1' when (r_MESSAGE_LENGTH_COUNTER = to_unsigned(15, 4)) else '0';

-- get input bit into shift register on every sample enable signal (bit value detection)
p_DETECT_IN_BIT_STATE_CHANGE : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_INPUT_EDGE_SHIFT <= "00";
		elsif(s_SAMPLE_AT_25 = '1') then
			r_INPUT_EDGE_SHIFT(1) <= manchester_in;
		elsif(s_SAMPLE_AT_75 = '1') then
			r_INPUT_EDGE_SHIFT(0) <= manchester_in;
		else
		end if;
	else
	end if;
end process p_DETECT_IN_BIT_STATE_CHANGE;

-- detect edge as close to the edge as possible (half-bit-time detection)
s_IN_BIT_MIDDLE <= '1' when ((r_SAMPLING_COUNTER > r_SAMPLING_COUNTER_AT_HALF_BIT*2 / 4) and (r_SAMPLING_COUNTER < r_SAMPLING_COUNTER_AT_HALF_BIT*2 * 3/4)) else '0';
s_AT_EDGE <= '1' when ((r_INPUT_BIT_TIME_SHIFT = "10") or (r_INPUT_BIT_TIME_SHIFT = "01")) else '0';

p_DETECT_BIT_TIME : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_INPUT_BIT_TIME_SHIFT <= "00";
		else
			r_INPUT_BIT_TIME_SHIFT <= (r_INPUT_BIT_TIME_SHIFT(0) & manchester_in);
		end if;
	end if;
	
	-- detect edge in the middle of bit time
	if((s_IN_BIT_MIDDLE = '1') and (s_AT_EDGE = '1')) then
		r_SAMPLING_COUNTER_AT_HALF_BIT <= r_SAMPLING_COUNTER;
		
	elsif ((r_STATE = v_START_BIT) and (s_AT_RISING_EDGE = '1')) then
		r_SAMPLING_COUNTER_AT_HALF_BIT <= r_START_BIT_BIT_TIME/2;
		
	end if;
end process p_DETECT_BIT_TIME;

-- create counter, based on which sampling times can be determined,
-- 	save currently decoded bit value when the read cycle comes to an end (MSB FIRST)
p_SAMPLING_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_SAMPLING_COUNTER <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
			
		-- reset on the measured bit-width (TODO)
		elsif(r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2) then
			r_SAMPLING_COUNTER <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
			
		-- reset sampling counter at the end of the start bit to be in sync with the bit stream
		elsif((r_STATE = v_START_BIT) and (s_AT_RISING_EDGE = '1')) then
			r_SAMPLING_COUNTER <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
		
		elsif((s_DECODE_MANCHESTER = '1') or (r_STATE = v_START_DELIMITER)) then
			r_SAMPLING_COUNTER <= r_SAMPLING_COUNTER + 1;
			
		else
			
		end if;
	end if;	
end process p_SAMPLING_COUNTER;

-- shift register for incoming decoded bits
p_DECODED_SHIFT : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_MAN_DATA_IN_SHIFT(15 downto 0) <= "0000000000000000";
			
		-- shift on the measured bit-width (TODO)
		elsif((r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2) and (s_DECODE_MANCHESTER = '1')) then
			r_MAN_DATA_IN_SHIFT(15 downto 0) <= (r_MAN_DATA_IN_SHIFT(14 downto 0) & r_CURRENT_BIT_DECODED);			-- MSB FIRST!!!
			
		--
		else
			
		end if;
	end if;	
end process p_DECODED_SHIFT;

-- counter that counts the number of decoded bits in the current word
--		it actually counts how many shifts have happened, therefore it needs to be reset at 16 and not 15
--		in the case of the message as well as 8 and not seven in the case of the CRC
p_MESSAGE_LENGTH_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, v_MVB_WORD_WIDTH_WIDTH+1);
			
		elsif((r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2) and (s_DECODE_MANCHESTER = '1')) then
			r_MESSAGE_LENGTH_COUNTER <= r_MESSAGE_LENGTH_COUNTER + 1;
			
		elsif((r_MESSAGE_LENGTH_COUNTER = to_unsigned(v_MVB_WORD_WIDTH, v_MVB_WORD_WIDTH_WIDTH+1))) then
			r_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, v_MVB_WORD_WIDTH_WIDTH+1);
			
		elsif(r_STATE = v_START_BIT) then
			r_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, v_MVB_WORD_WIDTH_WIDTH+1);
			
		end if;
	end if;
end process p_MESSAGE_LENGTH_COUNTER;

-- get edge direction of current bit, save value according to the manchester coding standard
-- save the value of the sampling counter for synchronization purposes
p_DECODE_BIT_VALUE : process (r_INPUT_EDGE_SHIFT)
begin
	case r_INPUT_EDGE_SHIFT is
		when "10" =>
			r_CURRENT_BIT_DECODED <= '0';
		when "01" =>
			r_CURRENT_BIT_DECODED <= '1';
		when others =>
			r_CURRENT_BIT_DECODED <= r_CURRENT_BIT_DECODED;
	end case;
end process p_DECODE_BIT_VALUE;


p_COUNT_MVB_WORDS : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_WORD_COUNTER <= to_unsigned(1, 5);
		
		-- when the data transmission starts, set the expected message length in the counter
		elsif((r_STATE = v_START_DELIMITER) and (r_START_DELIMITER_COUNTER = to_unsigned(16, 5)) and (r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2)) then
			case s_START_DELIMITER_VALUE_CHECK is
				when "01"	=>		
					r_WORD_COUNTER <= to_unsigned(1, 5);
				when "10"	=>		
					r_WORD_COUNTER <= unsigned(r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH);
				when others =>		r_WORD_COUNTER <= to_unsigned(1, 5);
			end case;
		-- subtract from the total words remaining after every 16 bit transfer
		elsif(true) then
		
		end if;
	end if;
end process p_COUNT_MVB_WORDS;


-- sample value at clk3 and clk11 (at 25% and 75%)
s_SAMPLE_AT_25 <= '1' when (r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2 / 4) else '0';
s_SAMPLE_AT_75 <= '1' when (r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2 * 3/4) else '0';
s_SAMPLE_MANCHESTER_INPUT <= '1' when (s_SAMPLE_AT_25 = '1') or (s_SAMPLE_AT_75 = '1') else '0';

--_____________________________RECEIVE START DELIMITER_____________________________--
-- In the start delimiter state, the input sequence will be sampled at double bitrate, because
--		manchester coding is ignored, and the delimiter is treated as a single 16 bit sequence.
-- The validity of the received sequence is checked after the full transmission, by the state machine.

p_RECEIVE_START_DELIMITER : process(clk)
begin
	if(rising_edge(clk)) then
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

--_____________________________CRC RECEPTION_____________________________--
-- CRC is already being received into r_MAN_DATA_IN_SHIFT, it will be saved to
-- 	r_CRC_IN after the CRC reception state is over with
s_CRC_READY <= '1' when ((r_MESSAGE_LENGTH_COUNTER = to_unsigned(8, 4))
										and (r_STATE = v_RECEIVE_CRC)) else '0';
										
--_____________________________END DELIMITER RECEPTION_____________________________--
-- the end delimiter is for EMD 1 BT LOW and 1 BT HIGH, emitted by whatever device
--		is currently sending data onto the bus. Therefore the end delimiter ends at the next falling edge.
s_END_OF_END_DELIMITER <= '1' when ((r_STATE = v_END_DELIMITER) and (s_AT_FALLING_EDGE = '1')) else '0';

--_____________________________TRANSMISSION STATE MACHINE_____________________________--
s_AT_RISING_EDGE <= '1' when (r_INPUT_BIT_TIME_SHIFT = "01") else '0';
s_AT_FALLING_EDGE <= '1' when (r_INPUT_BIT_TIME_SHIFT = "10") else '0';

-- how many cycles does the start bit last?
p_MEASURE_INITIAL_BIT_TIME : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_START_BIT_BIT_TIME <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
		elsif(r_STATE = v_START_BIT) then
			r_START_BIT_BIT_TIME <= r_START_BIT_BIT_TIME + 1;
		else
			r_START_BIT_BIT_TIME <= to_unsigned(0, v_SAMPLING_COUNTER_WIDTH);
		end if;
	else
	end if;
end process p_MEASURE_INITIAL_BIT_TIME;


p_TRANSMISSION_STATE_MACHINE : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_STATE <= v_IDLE;
			data_ready <= '0';
			
		-- idle --> next rising edge is a start bit
		elsif((r_STATE = v_IDLE) and (s_AT_RISING_EDGE = '1')) then
			r_STATE <= v_START_BIT;
			data_ready <= '0';
			
		-- start bit --> next rising edge is a start delimiter
		elsif((r_STATE = v_START_BIT) and (s_AT_RISING_EDGE = '1')) then
			r_STATE <= v_START_DELIMITER;
			
		-- if delimiter is valid, set its type, if it is not, return to idle (have to wait until the current cycle is finished or the reception will begin too early)
		elsif((r_STATE = v_START_DELIMITER) and (r_START_DELIMITER_COUNTER = to_unsigned(16, 5)) and (r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2)) then
			case s_START_DELIMITER_VALUE_CHECK is
				when "01"	=>		
					r_STATE <= v_RECEIVE_MASTER;
				when "10"	=>		
					r_STATE <= v_RECEIVE_SLAVE;
				when others =>		r_STATE <= v_IDLE;
			end case;
			
		elsif((r_STATE = v_RECEIVE_MASTER) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(v_MVB_WORD_WIDTH, v_MVB_WORD_WIDTH_WIDTH+1))) then
			r_LAST_RECEIVED_MASTER_DATA <= r_MAN_DATA_IN_SHIFT;		-- save master data
			r_STATE <= v_RECEIVE_CRC;
			
		elsif((r_STATE = v_RECEIVE_SLAVE) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(v_MVB_WORD_WIDTH, v_MVB_WORD_WIDTH_WIDTH+1))) then
			r_SLAVE_DATA_RECEIVED <= r_MAN_DATA_IN_SHIFT;		-- save slave message before more manchester stuff is received
			r_STATE <= v_RECEIVE_CRC;
			
		elsif((r_STATE = v_RECEIVE_CRC) and (s_CRC_READY = '1') and (r_SAMPLING_COUNTER = r_SAMPLING_COUNTER_AT_HALF_BIT*2)) then
			r_CRC_IN <= r_MAN_DATA_IN_SHIFT(7 downto 0); -- save CRC before more manchester stuff is received [MSB!!]
			r_STATE <= v_END_DELIMITER;
			
		elsif((r_STATE = v_END_DELIMITER) and (s_END_OF_END_DELIMITER = '1')) then
			r_STATE <= v_IDLE;
			data_ready <= '1';
			decoded_out <= r_SLAVE_DATA_RECEIVED;
		else
			--r_STATE 	<= v_IDLE;			-- throw error maybe?
		end if;
	else
	end if;
end process p_TRANSMISSION_STATE_MACHINE;


--_____________________________CREATING SETTINGS FOR THE NEXT TRANSMISSION_____________________________--

--	How many 16 bit MVB words long is the next slave data on the MVB bus going to contain?
p_DETERMINE_NEXT_MESSAGE_LENGTH : process(clk, r_LAST_RECEIVED_MASTER_DATA(15 downto 11))
begin
	case r_LAST_RECEIVED_MASTER_DATA(15 downto 12) is
		-- Process Data /w 16bit length, Mastership_Transfer, General_Event, Group_Event, Single_Event, Device_Status
		when "0000" | "1000" | "1001" | "1101" | "1110" | "1111" =>
			r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH <= to_unsigned(1, 5);
		
		-- Process Data /w 32bit length
		when "0001" =>
			r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH <= to_unsigned(2, 5);
		
		-- Process Data /w 64bit length
		when "0010" =>
			r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH <= to_unsigned(4, 5);
			
		-- Process Data /w 128bit length
		when "0011" =>
			r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH <= to_unsigned(8, 5);
		
		-- Process Data /w 256bit length, Message Data
		when "0100" | "1100" =>
			r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH <= to_unsigned(16, 5);
			
		-- Handle exceptions so the code compiles. This is reserved for custom stuff usually.
		when others =>
			r_NEXT_EXPECTED_SLAVE_MESSAGE_LENGTH <= to_unsigned(1, 5);
	end case;
end process p_DETERMINE_NEXT_MESSAGE_LENGTH;

end Behavioral;

