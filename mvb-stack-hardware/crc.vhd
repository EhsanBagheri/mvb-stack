----------------------------------------------------------------------------------
-- BME MIT CRC calculator based on the polynomial x7 + x6 + x5 + x2 + 1
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE ieee.numeric_std.ALL;

entity e_CRC is
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
			  wr 	: in  STD_LOGIC;
           serial_in : in  STD_LOGIC;
			  shift_zeroes : in STD_LOGIC;
			  crc_rdy		 : out  STD_LOGIC;
           crc_out : out  STD_LOGIC_VECTOR (7 downto 0));
end e_CRC;

architecture Behavioral of e_CRC is

-- parity bit emitter
component e_EVEN_PARITY_BIT_EMITTER
	port(
		input_vector :	in			 std_logic_vector(6 downto 0);
		parity_bit	 :	out		 std_logic
	);
end component;

signal parity_bit : std_logic;
signal input_vector : std_logic_vector(6 downto 0);

-- state machine constants
constant v_IDLE : std_logic_vector(1 downto 0) := "00";				-- no input
constant v_SHIFT_INPUT : std_logic_vector(1 downto 0) := "01";		-- calculate CRC for input
constant v_SHIFT_ZEROES : std_logic_vector(1 downto 0) := "10";	-- finish calculation by shifting 7 zeroes

-- state register
signal r_STATE	: std_logic_vector(1 downto 0);

-- shift register signals
signal s_SHR_LSB : std_logic;
signal s_CRC_SHIFT_REGISTER_NEXT : std_logic_vector(7 downto 0);
signal r_CRC_SHIFT_REGISTER : std_logic_vector(7 downto 0);
signal r_ZEROES_COUNTER : unsigned(3 downto 0);

signal s_PRE_NEGATION_OUT : std_logic_vector(7 downto 0);

begin

-----------------------------------------------------------------------------
--------------------------------CALCULATE CRC--------------------------------
-----------------------------------------------------------------------------

-- shift input or zeroes?
p_SELECT_LAST_BIT : process(clk, r_STATE)
begin
	case r_STATE is
		when v_SHIFT_INPUT => s_SHR_LSB <= serial_in;
		when v_SHIFT_ZEROES => s_SHR_LSB <= '0';
		when others => 
	end case;
end process p_SELECT_LAST_BIT;

-- Actual CRC calculation via a shift register:
-- x7 + x6 + x5 + x2 + 1
s_CRC_SHIFT_REGISTER_NEXT <= ((r_CRC_SHIFT_REGISTER(6) xor r_CRC_SHIFT_REGISTER(7)) &	-- x7
										(r_CRC_SHIFT_REGISTER(5) xor r_CRC_SHIFT_REGISTER(7))	&	-- x6
										r_CRC_SHIFT_REGISTER(4) &											-- x5
										r_CRC_SHIFT_REGISTER(3) &											-- x4
										(r_CRC_SHIFT_REGISTER(2) xor r_CRC_SHIFT_REGISTER(7)) &	-- x3
										r_CRC_SHIFT_REGISTER(1) &											-- x2
										(r_CRC_SHIFT_REGISTER(0) xor r_CRC_SHIFT_REGISTER(7)) &	-- x1
										s_SHR_LSB);
										
p_GENERATE_CRC : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_CRC_SHIFT_REGISTER <= "00000000";
			
		elsif(r_STATE = v_IDLE and wr = '1') then
			r_CRC_SHIFT_REGISTER <= "0000000" & serial_in;
		
		elsif(r_STATE = v_SHIFT_INPUT and wr = '1') then
			r_CRC_SHIFT_REGISTER <= s_CRC_SHIFT_REGISTER_NEXT;
			
		elsif(r_STATE = v_SHIFT_ZEROES and r_ZEROES_COUNTER > to_unsigned(0, 4)) then
			r_CRC_SHIFT_REGISTER <= s_CRC_SHIFT_REGISTER_NEXT;
		
		end if;
	end if;
end process p_GENERATE_CRC;

p_ZEROES_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_ZEROES_COUNTER <= to_unsigned(0, 4);
			
		elsif(r_STATE = v_SHIFT_INPUT and shift_zeroes = '1') then
			r_ZEROES_COUNTER <= to_unsigned(7, 4);
			
		elsif(r_STATE = v_SHIFT_ZEROES) then
			r_ZEROES_COUNTER <= r_ZEROES_COUNTER - 1;
			
		end if;
	end if;
end process p_ZEROES_COUNTER;

-----------------------------------------------------------------------------
--------------------------------GET PARITY BIT-------------------------------
-----------------------------------------------------------------------------
c_PARITY_BIT_EMITTER : e_EVEN_PARITY_BIT_EMITTER port map(
	input_vector => input_vector,
	parity_bit => parity_bit
);

input_vector <= s_CRC_SHIFT_REGISTER_NEXT(7 downto 1);
-----------------------------------------------------------------------------
--------------------------------STATE MACHINE--------------------------------
-----------------------------------------------------------------------------

s_PRE_NEGATION_OUT <= s_CRC_SHIFT_REGISTER_NEXT(7 downto 1) & parity_bit;

p_STATE_MACHINE : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_STATE <= v_IDLE;
			
		elsif(r_STATE = v_IDLE and wr = '1') then
			r_STATE <= v_SHIFT_INPUT;
			crc_rdy <= '0';
			
		elsif(r_STATE = v_SHIFT_INPUT and shift_zeroes = '1') then
			r_STATE <= v_SHIFT_ZEROES;
			
		elsif(r_STATE = v_SHIFT_ZEROES and r_ZEROES_COUNTER = to_unsigned(0, 4)) then
			r_STATE <= v_IDLE;
			crc_rdy <= '1';
			crc_out <= not s_PRE_NEGATION_OUT;
		
		end if;
	end if;
end process p_STATE_MACHINE;

end Behavioral;

