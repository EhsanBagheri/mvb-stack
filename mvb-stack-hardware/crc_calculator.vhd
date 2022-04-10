-- shift register for continuous CRC calculation
-- BME MIT 2022

-- The MVB cyclic redundancy check:
--		G(x) = x7 + x6 + x5 + x2 + 1
--		the 7 bit remainder is extended by an even parity bit
--		the eight bits are transmitted inverted

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE ieee.numeric_std.ALL;

entity e_CRC_CALCULATOR is
	Port(
		clk						:	in		std_logic;
		rst						:	in		std_logic;
		start_calculation		:	in		std_logic;										-- start shifting the value on serial_input
		read_input				:	in		std_logic;										-- there is a new valid bit on serial_input that should be read
		serial_input			:	in		std_logic;
		awaited_ipnut_length	:	in		std_logic_vector(6 downto 0);				-- how many bits long is the awaited message? (16, 32, 64)
		crc_output				:	out	std_logic_vector(7 downto 0)
	);
end e_CRC_CALCULATOR;

architecture Behavioral of e_CRC_CALCULATOR is

-- state machine constants
constant v_IDLE : std_logic_vector(1 downto 0) := "00";
constant v_SHIFT_INPUT : std_logic_vector(1 downto 0) := "01";
constant v_SHIFT_ZEROES : std_logic_vector(1 downto 0) := "10";

-- state machine signals
signal r_STATE	: std_logic_vector(1 downto 0);

-- message length calculation
signal r_MESSAGE_LENGTH_COUNTER : unsigned(6 downto 0);

-- CRC calculation
signal r_CRC_SHIFT_REGISTER : std_logic_vector(7 downto 0);
signal s_CRC_SHIFT_REGISTER_NEXT : std_logic_vector(7 downto 0);

begin

-- counting message length
p_MESSAGE_LENGTH_COUNTER : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_MESSAGE_LENGTH_COUNTER <= to_unsigned(64, 7);
			
		elsif(r_STATE = v_IDLE and start_calculation = '1') then
			r_MESSAGE_LENGTH_COUNTER <= unsigned(awaited_ipnut_length);
		
		-- count how many input bits are left
		elsif(r_STATE = v_SHIFT_INPUT and read_input = '1') then
			r_MESSAGE_LENGTH_COUNTER <= r_MESSAGE_LENGTH_COUNTER - 1;
		
		-- count how many zeroes have been shifted
		elsif(r_STATE = v_SHIFT_ZEROES) then
			r_MESSAGE_LENGTH_COUNTER <= r_MESSAGE_LENGTH_COUNTER + 1;
			
		else
	
		end if;
	end if;
end process p_MESSAGE_LENGTH_COUNTER;

-- generate CRC using a shift register
p_GENERATE_CRC : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_CRC_SHIFT_REGISTER <= "00000000";
			
		elsif(r_STATE = v_IDLE and start_calculation = '1') then
			r_CRC_SHIFT_REGISTER <= "00000000";
		
		elsif(r_STATE = v_SHIFT_INPUT and read_input = '1') then
			r_CRC_SHIFT_REGISTER <= s_CRC_SHIFT_REGISTER_NEXT;
			
		elsif(r_STATE = v_SHIFT_ZEROES) then
			r_CRC_SHIFT_REGISTER <= s_CRC_SHIFT_REGISTER_NEXT;
		
		end if;
	end if;
end process p_GENERATE_CRC;

p_CRC_SHIFT_NEXT_GENERATION : process(serial_input, r_CRC_SHIFT_REGISTER)
begin
	case r_STATE is
		when v_SHIFT_INPUT =>
			s_CRC_SHIFT_REGISTER_NEXT <= ((r_CRC_SHIFT_REGISTER(6) xor r_CRC_SHIFT_REGISTER(7)) &	-- x7
													(r_CRC_SHIFT_REGISTER(5) xor r_CRC_SHIFT_REGISTER(7))	&	-- x6
													r_CRC_SHIFT_REGISTER(4) &											-- x5
													r_CRC_SHIFT_REGISTER(3) &											-- x4
													(r_CRC_SHIFT_REGISTER(2) xor r_CRC_SHIFT_REGISTER(7)) &	-- x3
													r_CRC_SHIFT_REGISTER(1) &											-- x2
													(r_CRC_SHIFT_REGISTER(0) xor r_CRC_SHIFT_REGISTER(7)) &	-- x1
													serial_input);															-- x0
			
		when v_SHIFT_ZEROES =>
			s_CRC_SHIFT_REGISTER_NEXT <= ((r_CRC_SHIFT_REGISTER(6) xor r_CRC_SHIFT_REGISTER(7)) &	-- x7
													(r_CRC_SHIFT_REGISTER(5) xor r_CRC_SHIFT_REGISTER(7))	&	-- x6
													r_CRC_SHIFT_REGISTER(4) &											-- x5
													r_CRC_SHIFT_REGISTER(3) &											-- x4
													(r_CRC_SHIFT_REGISTER(2) xor r_CRC_SHIFT_REGISTER(7)) &	-- x3
													r_CRC_SHIFT_REGISTER(1) &											-- x2
													(r_CRC_SHIFT_REGISTER(0) xor r_CRC_SHIFT_REGISTER(7)) &	-- x1
													'0');																		-- x0																	-- x0
		when others =>
			s_CRC_SHIFT_REGISTER_NEXT <= r_CRC_SHIFT_REGISTER;

	end case;
end process p_CRC_SHIFT_NEXT_GENERATION;

-- state machine
p_STATE_MACHINE : process(clk)
begin
	if(rising_edge(clk)) then
		if(rst = '1') then
			r_STATE <= v_IDLE;
			
		elsif(r_STATE = v_IDLE and start_calculation = '1') then
			r_STATE <= v_SHIFT_INPUT;
			
		elsif(r_STATE = v_SHIFT_INPUT and r_MESSAGE_LENGTH_COUNTER = to_unsigned(0, 8)) then
			r_STATE <= v_SHIFT_ZEROES;
			
		elsif(r_STATE = v_SHIFT_ZEROES AND r_MESSAGE_LENGTH_COUNTER = to_unsigned(7, 8)) then
			r_STATE <= v_IDLE;
			-- TODO: emit result negated with parity bit
		
		end if;
	end if;
end process p_STATE_MACHINE;

end Behavioral;

