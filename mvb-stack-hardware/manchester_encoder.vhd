-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity e_MANCHESTER_ENCODER is
	Port(
		clk						:	in			std_logic;
		rst						:	in			std_logic;
		start_transmission 	    :	in			std_logic;								-- should be a single clock period long pulse
		data_length				:	in			std_logic_vector(4 downto 0); 	        -- how many times 16 bits?
		frame_type              :   in          std_logic;                              -- 0 when slave frame, 1 when master frame
		--
		din						:	in			std_logic_vector(7 downto 0);		    -- input data in 8 bit data words (will be stored in FIFO)
		wr_en					: 	in			std_logic;								-- FIFO write enable signal, when active, din will be saved to FIFO
		--
		encoded_out				:	out		    std_logic								-- serial output onto the MVB bus
	);
end entity e_MANCHESTER_ENCODER;



architecture Behavioral of e_MANCHESTER_ENCODER is

constant v_MVB_WORD_WIDTH_WIDTH : integer := 4;
constant v_MVB_WORD_WIDTH : integer := 2**v_MVB_WORD_WIDTH_WIDTH;	-- MVB data word width is per industry standard 16 bits, which fits on 4 bits
constant v_BIT_TIME : integer := 40;										-- how many clk periods doeas a bit time period take?

-- state machine constants:
constant v_IDLE : std_logic_vector(2 downto 0) := "000";
constant v_START_SEQUENCE : std_logic_vector(2 downto 0) := "001";
constant v_EMIT_MESSAGE : std_logic_vector(2 downto 0) := "010";
constant v_EMIT_CRC : std_logic_vector(2 downto 0) := "011";
constant v_END_DELIMITER : std_logic_vector(2 downto 0) := "100";

-- constants for delimiter detection (start bit not included)
constant v_MASTER_DELIMITER : std_logic_vector(15 downto 0) := "1100011100010101";
constant v_SLAVE_DELIMITER : std_logic_vector(15 downto 0) := "1010100011100011";

---------------------------------------------------------------------
---------------------- THIRD PARTY COMPONENTS -----------------------
---------------------------------------------------------------------


COMPONENT fifo_generator_0
  PORT (
    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC;
    din : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    wr_en : IN STD_LOGIC;
    rd_en : IN STD_LOGIC;
    dout : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    full : OUT STD_LOGIC;
    empty : OUT STD_LOGIC
  );
END COMPONENT;

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
signal r_ENCODED_OUT_SHIFT	    :	std_logic_vector(17 downto 0);		-- mini shift register, containing a single manchester coded bit
signal r_MESSAGE_LENGTH_COUNTER	:	unsigned(4 downto 0);		        -- how many times has r_OUT_SHIFT been shifted since the last bit of data has been loaded
signal r_DATA_LENGTH_COUNTER	:	unsigned(5 downto 0);			    -- how many times 8 bits does the messaged data word contain?
signal r_WORD_GROUP_COUNTER     :   unsigned(3 downto 0);               -- how many 8 bit words until the next CRC?
signal r_WORD_GROUP_COUNTER_INIT_VALUE : unsigned(3 downto 0);
signal s_RESET_MLC	            :	std_logic;					        -- 1 when the transmission is about to reach a new chunk of message (always new state except when emitting data message)
signal s_MLC_NEARING_RESET	    :	std_logic;							-- 1 when the transmission is about to reach a new chunk of message, but isn't at a bit end yet
signal s_MESSAGE_WORD_ENCODED   :   std_logic_vector(17 downto 0);      -- current output of the FIFO in manchester code
signal s_CRC_ENCODED            :   std_logic_vector(15 downto 0);      -- manchester encoded CRC bits (encoded from the output of the crc calc module)


begin

----------------------------------------------------------------
--------------------- EXTERNAL COMPONENTS ----------------------
----------------------------------------------------------------

-- adding FIFO memory for 8 bit input data
FIFO : fifo_generator_0
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
s_AT_FULL_BT <= '1' when r_BT_COUNTER = to_unsigned(v_BIT_TIME-1, 8) else '0';	    -- data bit change

p_BIT_TIME_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then 
		if(rst = '1') then
			r_BT_COUNTER <= to_unsigned(0, 8);
			
		elsif(s_AT_FULL_BT = '1' or start_transmission = '1') then
			r_BT_COUNTER <= to_unsigned(0, 8);
			
		else
			r_BT_COUNTER <= r_BT_COUNTER + 1;
			
		end if;
	end if;

end process p_BIT_TIME_COUNTER;

--_____________________________TRANSMISSION SCHEDULING_____________________________--
s_MLC_NEARING_RESET <= '1' when
									((r_STATE = v_START_SEQUENCE) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(8, 5))) or
									((r_STATE = v_EMIT_MESSAGE) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(7, 5))) or
									((r_STATE = v_EMIT_CRC) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(7, 5))) or
									((r_STATE = v_END_DELIMITER) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(1, 5)))
									else '0';
									
s_RESET_MLC <= '1' when ((start_transmission = '1') or (s_AT_FULL_BT = '1' and s_MLC_NEARING_RESET = '1')) else '0';

p_MESSAGE_LENGTH_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, 5);
			
		elsif(s_RESET_MLC = '1') then
			r_MESSAGE_LENGTH_COUNTER <= to_unsigned(0, 5);
			
		elsif(s_AT_FULL_BT = '1') then
			r_MESSAGE_LENGTH_COUNTER <= r_MESSAGE_LENGTH_COUNTER + 1;
		
		end if;
	end if;
end process p_MESSAGE_LENGTH_COUNTER;


-- how many times 8 bits of data needs to be emitted during the v_EMIT_MESSAGE state?
p_DATA_LENGTH_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1' or start_transmission = '1') then
			r_DATA_LENGTH_COUNTER <= unsigned(data_length & '0');    -- multiplied by 2
		
		elsif(r_STATE = v_EMIT_MESSAGE and s_RESET_MLC = '1') then
			r_DATA_LENGTH_COUNTER <= r_DATA_LENGTH_COUNTER - 1;
			
		end if;
	end if;
end process p_DATA_LENGTH_COUNTER;

p_WORD_GROUP_COUNTER : process(clk)
begin
    if(rising_edge(clk)) then
        if(rst = '1') then
            r_WORD_GROUP_COUNTER <= to_unsigned(1, 4);
            
        elsif(start_transmission = '1') then
       		
       		-- how many 8 bit words per word group?
			case unsigned(data_length) is 
			    when to_unsigned(1, 5) =>  
			         r_WORD_GROUP_COUNTER_INIT_VALUE <= to_unsigned(2, 4);
			         r_WORD_GROUP_COUNTER <= to_unsigned(2, 4);
			    when to_unsigned(2, 5) =>  
			         r_WORD_GROUP_COUNTER_INIT_VALUE <= to_unsigned(4, 4);
			         r_WORD_GROUP_COUNTER <= to_unsigned(4, 4);
			    when to_unsigned(4, 5) =>   
			         r_WORD_GROUP_COUNTER_INIT_VALUE <= to_unsigned(8, 4);
			         r_WORD_GROUP_COUNTER <= to_unsigned(8, 4);
			    when to_unsigned(8, 5) =>  
			         r_WORD_GROUP_COUNTER_INIT_VALUE <= to_unsigned(8, 4);
			         r_WORD_GROUP_COUNTER <= to_unsigned(8, 4);
			    when to_unsigned(16, 5) =>  
			         r_WORD_GROUP_COUNTER_INIT_VALUE <= to_unsigned(8, 4);
			         r_WORD_GROUP_COUNTER <= to_unsigned(8, 4);
			    when others => 
			         r_WORD_GROUP_COUNTER_INIT_VALUE <= to_unsigned(2, 4);
			         r_WORD_GROUP_COUNTER <= to_unsigned(2, 4);
			end case;
			
		elsif(r_STATE = v_EMIT_CRC) then
		    r_WORD_GROUP_COUNTER <= r_WORD_GROUP_COUNTER_INIT_VALUE;
		    
		elsif(rd_en = '1' and r_STATE = v_EMIT_MESSAGE) then
		    r_WORD_GROUP_COUNTER <= r_WORD_GROUP_COUNTER - 1;
		    
		end if;
    end if;
end process p_WORD_GROUP_COUNTER;

--_____________________________MANCHESTER ENCODING AND TRANSMISSION_____________________________--
-- The idea is as follows: The message will be loaded into a shift register and instantly 
--      encoded into manchester code as it is being read from the FIFO. 

p_ENCODED_OUT_SHIFT :	process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_ENCODED_OUT_SHIFT <= "000000000000000000";
		
		elsif(start_transmission = '1' and frame_type = '0') then
		    r_ENCODED_OUT_SHIFT <= "10" & v_SLAVE_DELIMITER;
		    
		elsif(start_transmission = '1' and frame_type = '1') then
		    r_ENCODED_OUT_SHIFT <= "10" & v_MASTER_DELIMITER;
		
		-- load the next CRC and the end delimiter afterwards (end delimiter will be skipped if the message is not over yet)
		elsif((r_STATE = v_EMIT_MESSAGE) and (r_WORD_GROUP_COUNTER  = to_unsigned(0, 4))) then
		    r_ENCODED_OUT_SHIFT <= s_CRC_ENCODED & "11";
		    
		elsif(s_RESET_MLC = '1' and (r_STATE = v_EMIT_MESSAGE or r_STATE = v_START_SEQUENCE)) then
		    r_ENCODED_OUT_SHIFT <= s_MESSAGE_WORD_ENCODED;
		    
	    elsif(s_RESET_MLC = '1' and (r_STATE = v_EMIT_CRC and r_DATA_LENGTH_COUNTER > to_unsigned(0, 6))) then
		    r_ENCODED_OUT_SHIFT <= s_MESSAGE_WORD_ENCODED;
		    
		elsif(r_STATE = v_IDLE) then
		    r_ENCODED_OUT_SHIFT <= "000000000000000000";
		    
		elsif(s_AT_FULL_BT = '1' or s_AT_HALF_BT = '1') then
		    r_ENCODED_OUT_SHIFT <= r_ENCODED_OUT_SHIFT(16 downto 0) & '0';
		
        end if;
	end if;
end process p_ENCODED_OUT_SHIFT;

encoded_out <= r_ENCODED_OUT_SHIFT(17);

-- decode the data output of the FIFO
p_DECODE_MESSAGE_WORD : process(dout)
begin
    case dout(7) is
        when '0' => s_MESSAGE_WORD_ENCODED(17 downto 16) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(17 downto 16) <= "01";
        when others =>
    end case;
    
    case dout(6) is
        when '0' => s_MESSAGE_WORD_ENCODED(15 downto 14) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(15 downto 14) <= "01";
        when others =>
    end case;
    
    case dout(5) is
        when '0' => s_MESSAGE_WORD_ENCODED(13 downto 12) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(13 downto 12) <= "01";
        when others =>
    end case;
    
    case dout(4) is
        when '0' => s_MESSAGE_WORD_ENCODED(11 downto 10) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(11 downto 10) <= "01";
        when others =>
    end case;
    
    case dout(3) is
        when '0' => s_MESSAGE_WORD_ENCODED(9 downto 8) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(9 downto 8) <= "01";
        when others =>
    end case;
    
    case dout(2) is
        when '0' => s_MESSAGE_WORD_ENCODED(7 downto 6) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(7 downto 6) <= "01";
        when others =>
    end case;
    
    case dout(1) is
        when '0' => s_MESSAGE_WORD_ENCODED(5 downto 4) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(5 downto 4) <= "01";
        when others =>
    end case;
    
    case dout(0) is
        when '0' => s_MESSAGE_WORD_ENCODED(3 downto 2) <= "10";
        when '1' => s_MESSAGE_WORD_ENCODED(3 downto 2) <= "01";
        when others =>
    end case;
    
    s_MESSAGE_WORD_ENCODED(1 downto 0) <= "00";
end process p_DECODE_MESSAGE_WORD;



--_____________________________CRC_____________________________--
s_CRC_ENCODED <= "0000000000000000";    -- [PLACEHOLDER] for the CRC calculator module

--_____________________________DATA SCHEDULING ACCORDING TO EMISSION SCHEDULING_____________________________--
--	The proper data needs to be inserted into r_ENCODED_OUT_SHIFT based on r_STATE and r_MESSAGE_LENGTH_COUNTER.
-- All signals necessary to schedule this are given elsewhere.
-- Generates: rd_en

-- New data has to be read when
rd_en <= '1' when 
	-- there are still message bits left in the FIFO
	(((r_STATE = v_EMIT_MESSAGE) and (r_MESSAGE_LENGTH_COUNTER = to_unsigned(7, 5)) 
			and (r_DATA_LENGTH_COUNTER > to_unsigned(0, 4)) and (s_AT_HALF_BT = '1')) or
	-- the start sequence is at its last bit
	((r_STATE = v_START_SEQUENCE) and(r_MESSAGE_LENGTH_COUNTER = to_unsigned(8, 5)) 
			and (s_AT_HALF_BT = '1'))) else '0';	

--_____________________________STATE MACHINE_____________________________--

p_TRANSMISSION_STATE_MACHINE : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_STATE <= v_IDLE;
		
		elsif((r_STATE = v_IDLE) and (start_transmission = '1')) then
			r_STATE <= v_START_SEQUENCE;
			
		elsif((r_STATE = v_START_SEQUENCE) and (s_RESET_MLC = '1')) then
			r_STATE <= v_EMIT_MESSAGE;
			
		elsif((r_STATE = v_EMIT_MESSAGE) and (s_RESET_MLC = '1') and (r_WORD_GROUP_COUNTER = to_unsigned(0, 3))) then
			r_STATE <= v_EMIT_CRC;
			
        -- return to emitting message if there are words to be encoded left
		elsif((r_STATE = v_EMIT_CRC) and (s_RESET_MLC = '1')) then
		    if(r_DATA_LENGTH_COUNTER = to_unsigned(0, 6)) then
			    r_STATE <= v_END_DELIMITER;
			else
			    r_STATE <= v_EMIT_MESSAGE;
			end if;

		elsif((r_STATE = v_END_DELIMITER) and (s_RESET_MLC = '1')) then
			r_STATE <= v_IDLE;

		end if;

	end if;
end process p_TRANSMISSION_STATE_MACHINE;



end Behavioral;























