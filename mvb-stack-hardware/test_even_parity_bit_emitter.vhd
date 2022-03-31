-- testbench for the iSim simulation of the even parity bit emitter

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity test_parity_bit_emitter is
end test_parity_bit_emitter;

architecture Behavioral of test_parity_bit_emitter is

component e_EVEN_PARITY_BIT_EMITTER is
	Port(	
		input_vector :	in			 std_logic_vector(6 downto 0);
		parity_bit	 :	out		 std_logic
		);
end component e_EVEN_PARITY_BIT_EMITTER;

signal r_INPUT_TEST_VECTOR : std_logic_vector(6 downto 0);
signal parity_bit : std_logic;

begin

	tested_emitter: e_EVEN_PARITY_BIT_EMITTER port map(
		input_vector => r_INPUT_TEST_VECTOR,
		parity_bit => parity_bit
	);
	
	
	p_TEST_PROCESS : process
	begin
		r_INPUT_TEST_VECTOR <= "1110001";
		wait for 100 ns;
		r_INPUT_TEST_VECTOR <= "0000000";
		wait for 100 ns;
		r_INPUT_TEST_VECTOR <= "0101010";
		wait for 100 ns;
		r_INPUT_TEST_VECTOR <= "1111110";
	end process p_TEST_PROCESS;


end Behavioral;