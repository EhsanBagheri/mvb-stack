-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity e_MANCHESTER_ENCODER is
	Port(
		clk						:	in			std_logic;
		rst						:	in			std_logic;
		start_transmission 	:	in			std_logic;								-- should be a single clock period long pulse
		data_length				:	in			unsigned(3 downto 0); 				-- how many times 16 bits?
		--
		din						:	in			std_logic_vector(7 downto 0);		-- input data in 8 bit data words (will be stored in FIFO)
		wr_en						: 	in			std_logic;								-- FIFO write enable signal, when active, din will be saved to FIFO
		--
		encoded_out				:	out		std_logic								-- serial output onto the MVB bus
	);
end entity e_MANCHESTER_ENCODER;



architecture Behavioral of e_MANCHESTER_ENCODER is

constant v_MVB_WORD_WIDTH_WIDTH : integer := 4;
constant v_MVB_WORD_WIDTH : integer := 2**v_MVB_WORD_WIDTH_WIDTH;	-- MVB data word width is per industry standard 16 bits, which fits on 4 bits
constant v_BIT_TIME : integer := 40;										-- how many clk periods doeas a bit time period take?

-- state machine constants:
constant v_IDLE : std_logic_vector(2 downto 0) := "000";
constant v_START_BIT : std_logic_vector(2 downto 0) := "001";
constant v_START_DELIMITER : std_logic_vector(2 downto 0) := "010";
constant v_EMIT_MESSAGE : std_logic_vector(2 downto 0) := "011";
constant v_EMIT_CRC : std_logic_vector(2 downto 0) := "100";
constant v_END_DELIMITER : std_logic_vector(2 downto 0) := "101";

-- constants for delimiter detection (start bit not included)
constant v_MASTER_DELIMITER : std_logic_vector(15 downto 0) := "1100011100010101";
constant v_SLAVE_DELIMITER : std_logic_vector(15 downto 0) := "1010100011100011";

---------------------------------------------------------------
---------------------- INTERNAL SIGNALS -----------------------
---------------------------------------------------------------

-- FIFO signals that are not inputs
signal rd_en	:	std_logic;
signal dout		:	std_logic_vector(7 downto 0);
signal full		:	std_logic;
signal empty	:	std_logic;

-- state machine signals (controlling the emission of encoded data)
signal r_STATE	:	std_logic_vector(2 downto 0);

-- signals used for determining bit time
signal r_BT_COUNTER	:	unsigned(7 downto 0);		-- counter based on which bit time related decisions are made
signal s_AT_HALF_BT	:	std_logic;
signal s_AT_FULL_BT	:	std_logic;

-- signals used for message emission
signal r_OUT_SHIFT	:	std_logic_vector(17 downto 0);			-- shift register containing the current message vector (MSB <-- LSB)
signal r_ENCODED_OUT_SHIFT	:	std_logic_vector(1 downto 0);		-- mini shift register, containing a single manchester coded bit
signal r_MESSAGE_LENGTH_COUNTER	:	unsigned(3 downto 0);		-- how many times has r_OUT_SHIFT been shifted since the last bit of data has been loaded
signal r_DATA_LENGTH_COUNTER	:	unsigned(3 downto 0);			-- how many times 16 bits does the messaged data word contain?
signal s_RESET_MLC	:	std_logic;										-- 1 when the transmission is about to reach a new chunk of message (always new state except when emitting data message)
signal s_ENCODE_MANCHESTER	:	std_logic;								-- does the data word in r_OUT_SHIFT need to be manchester encoded?



begin

----------------------------------------------------------------
--------------------- EXTERNAL COMPONENTS ----------------------
----------------------------------------------------------------

-- adding FIFO memory for 8 bit input data
FIFO : wrapped_fifo0
  PORT MAP (
    clk => clk,
    rst => rst,
    din => din,
    wr_en => wr_en,
    rd_en => rd_en,
    dout => dout,
    full => full,
    empty => empty
  );

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------

--_____________________________BIT TIME COUNTER_____________________________--
s_AT_HALF_BT <= '1' when r_BT_COUNTER = to_unsigned(v_BIT_TIME/2-1, 8) else '0';	-- manchester code edge
s_AT_FULL_BT <= '1' when r_BT_COUNTER = to_unsigned(v_BIT_TIME-1, 8) else '0';	-- data bit change

p_BIT_TIME_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then 
		if(rst = '1') then
			r_BT_COUNTER <= to_unsigned(0, 8);
			
		elsif(s_AT_FULL_BT = '1') then
			r_BT_COUNTER <= to_unsigned(0, 8);
			
		else
			r_BT_COUNTER <= r_BT_COUNTER + 1;
			
		end if;
	end if;

end process p_BIT_TIME_COUNTER;

--_____________________________TRANSMISSION SCHEDULING_____________________________--
s_RESET_MLC <= '1' when	((r_STATE = v_START_BIT) and (p_MESSAGE_LENGTH_COUNTER = to_unsigned(1, 4))) or
								((r_STATE = v_START_DELIMITER) and (p_MESSAGE_LENGTH_COUNTER = to_unsigned(15, 4))) or
								((r_STATE = v_EMIT_MESSAGE) and (p_MESSAGE_LENGTH_COUNTER = to_unsigned(15, 4))) or
								((r_STATE = v_EMIT_CRC) and (p_MESSAGE_LENGTH_COUNTER = to_unsigned(15, 4))) or
								((r_STATE = v_END_DELIMITER) and (p_MESSAGE_LENGTH_COUNTER = to_unsigned(1, 4)))
								else '0';

p_MESSAGE_LENGTH_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			p_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, 4);
			
		elsif(s_RESET_MLC = '1') then
			p_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, 4);
			
		elsif((s_AT_HALF_BT = '1') or (s_AT_FULL_BT = '1')) then
			p_MESSAGE_LENGTH_COUNTER <= p_MESSAGE_LENGTH_COUNTER + 1;
		
		end if;
	end if;
end process p_MESSAGE_LENGTH_COUNTER;


-- how many times 8 bits of data needs to be emitted during the v_EMIT_MESSAGE state?
p_DATA_LENGTH_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1' or start_transmission = '1') then
			r_DATA_LENGTH_COUNTER <= 2 * data_length;
		
		elsif(r_STATE = v_EMIT_MESSAGE and s_RESET_MLC = '1') then
			r_DATA_LENGTH_COUNTER <= r_DATA_LENGTH_COUNTER - 1;
			
		end if;
	end if;
end process p_DATA_LENGTH_COUNTER;

--_____________________________MANCHESTER ENCODING AND TRANSMISSION_____________________________--
-- The idea is as follows: r_OUT_SHIFT is a register, into which the next emitted word will be loaded,
--		each time there are only two bits left of the current message. This is scheduled by p_MESSAGE_LENGTH_COUNTER
--		as well as p_DATA_LENGTH_COUNTER to a certain capacity.
-- The MSB  of r_OUT_SHIFT is then decoded into r_ENCODED_OUT_SHIFT at every BT as a manchester coded
--		bit, then is shifted towards MSB at BT/2. The MSB of this register is the serial manchester output
--		of the module.

s_ENCODE_MANCHESTER <= '1' when ((r_STATE = v_START_BIT) and (r_STATE = v_EMIT_MESSAGE) and (r_STATE = v_EMIT_CRC)) else '0';

p_ENCODED_OUT_SHIFT :	process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_ENCODED_OUT_SHIFT <= "00";
		
		-- encode bit that is going to be transmitted
		elsif(s_AT_FULL_BT = '1') then
			case (r_OUT_SHIFT(17) & s_ENCODE_MANCHESTER) is
				-- encode
				when "11" => r_ENCODED_OUT_SHIFT <= "01";
				when "01" => r_ENCODED_OUT_SHIFT <= "10";
				-- don't encode
				when "10" => r_ENCODED_OUT_SHIFT <= "11";
				when "00" => r_ENCODED_OUT_SHIFT <= "00";
				
				when others =>
			end case;
		
		-- shift to send second value of manchester encoded message bit
		elsif(s_AT_HALF_BT = '1') then
			r_ENCODED_OUT_SHIFT <= (r_ENCODED_OUT_SHIFT(0) & r_ENCODED_OUT_SHIFT(1));
		end if;
	end if;
end process p_ENCODED_OUT_SHIFT;

-- MSB of r_ENCODED_OUT_SHIFT is the serial manchester output directly onto the bus
--		with the exception of the start delimiter.
p_EMISSION	:	process(r_STATE)
begin
	case r_STATE is
		when v_START_DELIMITER => encoded_out <= r_OUT_SHIFT(17);
		when others => encoded_out <= r_ENCODED_OUT_SHIFT(1);
	end case;
end process p_EMISSION;

--_____________________________DATA SCHEDULING ACCORDING TO EMISSION SCHEDULING_____________________________--
--	The proper data needs to be inserted into r_OUT_SHIFT based on r_STATE and r_MESSAGE_LENGTH_COUNTER.
-- All signals necessary to schedule this are given elsewhere.
-- This part of the hardware only generates signals that control the FIFO.

rd_en <= '1' when (((r_STATE = v_EMIT_MESSAGE) and (s_RESET_MLC = '1') and 
							(r_DATA_LENGTH_COUNTER > to_unsigned(0, 4))) or
							((r_STATE = v_START_DELIMITER) and
							(s_RESET_MLC = '1'))) else '0';

p_DATA_SCHEDULING	:	process(clk)
begin
	if(rising_edge(clk)) then
		-- at the start of the transmission, load the start bit and the start delimiter
		if((r_STATE = v_IDLE) & (start_transmission = '1')) then
			r_OUT_SHIFT <= '1' & v_SLAVE_DELIMITER & '0';
		
		-- when emitting the last bit of the previous message, load the next message
		elsif(rd_en = '1') then
			r_OUT_SHIFT <= dout & "0000000000";
			
		-- when emitting the last bit of the last message word, emit CRC + end delimiter [PLACEHOLDER]
		elsif((r_STATE = v_EMIT_MESSAGE) & (s_RESET_MLC = '1') & (r_DATA_LENGTH_COUNTER = to_unsigned(0, 4))) then
			r_OUT_SHIFT <= "000000001100000000";
			
		-- shift the register at every emitted bit
		elsif((r_STATE /= v_START_DELIMITER) and (s_AT_FULL_BT = '1')) then
			r_OUT_SHIFT <= r_OUT_SHIFT(16 downto 0) & '0';
		elsif((r_STATE = v_START_DELIMITER) and (s_AT_HALF_BT = '1')) then
			r_OUT_SHIFT <= r_OUT_SHIFT(16 downto 0) & '0';
		end if;
	end if;
end process p_DATA_SCHEDULING;

--_____________________________STATE MACHINE_____________________________--

p_TRANSMISSION_STATE_MACHINE : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_STATE <= v_IDLE;
			
		elsif((r_STATE = v_IDLE) & (start_transmission = '1')) then
			r_STATE <= v_START_BIT;
		
		-- in the current version, behaving as a slave is assumed
		elsif((r_STATE = v_START_BIT) & (s_RESET_MLC = '1')) then
			r_STATE <= v_START_DELIMITER;
			
		elsif((r_STATE = v_START_DELIMITER) & (s_RESET_MLC = '1')) then
			r_STATE <= v_EMIT_MESSAGE;
			
		elsif((r_STATE = v_EMIT_MESSAGE) & (s_RESET_MLC = '1') & (r_DATA_LENGTH_COUNTER = to_unsigned(0, 4))) then
			r_STATE <= v_EMIT_CRC;
			
		elsif((r_STATE = v_EMIT_CRC) & (s_RESET_MLC = '1')) then
			r_STATE <= v_END_DELIMITER;

		elsif((r_STATE = v_END_DELIMITER) & (s_RESET_MLC = '1')) then
			r_STATE <= v_IDLE;

		end if;

	end if;
end process p_TRANSMISSION_STATE_MACHINE;



end Behavioral;























