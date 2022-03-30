-- cascaded xor gates for even parity bit emission
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity e_EVEN_PARITY_BIT_EMITTER is
	Port(
		input_vector :	in			 std_logic_vector(6 downto 0);
		parity_bit	 :	out		 std_logic
		);
end entity e_EVEN_PARITY_BIT_EMITTER;

architecture Behavioral of e_EVEN_PARITY_BIT_EMITTER is

signal s_TIER0 : std_logic;
signal s_TIER1 : std_logic;
signal s_TIER2 : std_logic;
signal s_TIER3 : std_logic;
signal s_TIER4 : std_logic;

begin

-- Emits 1, when there are an odd number of 1s in the vector,
--		as 1s in a XOR gate "cancel each other out".
s_TIER0 <= input_vector(0) xor input_vector(1);
s_TIER1 <= input_vector(2) xor s_TIER0;
s_TIER2 <= input_vector(3) xor s_TIER1;
s_TIER3 <= input_vector(4) xor s_TIER2;
s_TIER4 <= input_vector(5) xor s_TIER3;
parity_bit <= input_vector(6) xor s_TIER4;

end Behavioral;

