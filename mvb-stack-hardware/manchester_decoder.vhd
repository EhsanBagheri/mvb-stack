-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity manchester_decoder is
    Port ( clk16x : in  std_logic;										-- 16x clock input for clock recovery and oversampling
			  rst : in std_logic;
			  rdn : in std_logic;											-- control signal initiates read operation
           manchester_in : in  std_logic;								-- incoming serial manchester-coded data
           decoded_out : out  std_logic_vector(7 downto 0);		-- outgoing data word
			  data_ready : out	std_logic								-- indicates that the decoded_out data is ready
			  );								
end manchester_decoder;

architecture Behavioral of manchester_decoder is

component four_bit_counter is
    Port ( rst,clk,up_dwn : in std_logic;
           output: out std_logic_vector(0 to 3));
end component four_bit_counter;

---------------------------------------------------------------
---------------------- INTERNAL SIGNALS -----------------------
---------------------------------------------------------------

-- create internal registers for edge detection:
signal man_data_in1 : std_logic;
signal man_data_in2 : std_logic;

-- controls word size and sequences decoder through operations
signal no_bits_recieved : std_logic;

-- internal 1x clock signal and clock enable
signal clk1x : std_logic;
signal clk1x_en : std_logic;

-- variable used by the counter to determine end count
signal first : std_logic;

-- counter for sampling at 25% clk and 75% clk and sample enable signal
signal fourth_counter : std_logic_vector(3 downto 0);
signal sample_manchester_input : std_logic;

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin

-- create counter that counts from 0x00 to 0xFF
sampling_counter: four_bit_counter port map(
	rst => rst,
	clk => clk16x,
	up_dwn => '0',
	output => fourth_counter
);

-- sample value at clk3 and clk11
sample_manchester_input <= '1' when (fourth_counter = "0011") or (fourth_counter = "1011") else '0';



end Behavioral;

