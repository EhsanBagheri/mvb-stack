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
signal r_ENCODED_OUT_SHIFT	:	std_logic_vector(17 downto 0);	-- shift register containing the current message vector (MSB <-- LSB)
signal r_MESSAGE_LENGTH_COUNTER	:	unsigned(3 downto 0);		-- how many times has r_ENCODED_OUT_SHIFT been shifted since the last bit of data has been loaded
signal r_DATA_LENGTH_COUNTER	:	unsigned(3 downto 0);			-- how many times 16 bits does the messaged data word contain?
signal s_RESET_MLC	:	std_logic;										-- 1 when the transmission is about to reach a new chunk of message (always new state except when emitting data message)



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
s_AT_HALF_BT <= '1' when r_BT_COUNTER = to_unsigned(v_BIT_TIME/2-1, 8) else '0';
s_AT_FULL_BT <= '1' when r_BT_COUNTER = to_unsigned(v_BIT_TIME-1, 8) else '0';

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
			
		else
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
			
		elsif((r_STATE = v_EMIT_MESSAGE) & (s_RESET_MLC = '1')) then
			r_STATE <= v_EMIT_CRC;
			
		elsif((r_STATE = v_EMIT_CRC) & (s_RESET_MLC = '1')) then
			r_STATE <= v_END_DELIMITER;

		elsif((r_STATE = v_END_DELIMITER) & (s_RESET_MLC = '1')) then
			r_STATE <= v_IDLE;

		end if;

	end if;
end process p_TRANSMISSION_STATE_MACHINE;



end Behavioral;























