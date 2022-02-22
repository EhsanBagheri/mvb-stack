-- Manchester signal decoder for the MVB protocol
-- 2022 BME MIT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity manchester_decoder is
    Port ( clk16x : in  std_logic;										-- 16x clock input for clock recovery and oversampling
			  rst : in std_logic;
			  rdn : in std_logic;											-- control signal initiates read operation
           manchester_in : in  std_logic;								-- incoming serial manchester-coded data
           decoded_out : out  std_logic_vector(7 downto 0);		-- outgoing data word
			  data_ready : out	std_logic								-- indicates that the decoded_out data is ready
			  );								
end manchester_decoder;

architecture Behavioral of manchester_coder is

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
signal fourth_counter : std_logic_vector(4 downto 0);
signal sample_manchester_input : std_logic;

---------------------------------------------------------------
------------------- BEHAVIORAL DESCRIPTION --------------------
---------------------------------------------------------------
begin

-- sample on every 4th and every 12th 16x clock rise
process(clk16x, rst)
	begin
		if(rst = '1')then
			fourth_counter <= "0000";
		elsif(rising_edge(clk16x))then
			fourth_counter <= fourth_counter + 1;
		end if;
	end process;

process(clk16x, fourth_counter)
	begin
		if(fourth_counter = '3')then
			sample_manchester_input <= '1';
		elsif(fourth_counter = "11")then
			sample_manchester_input <= '1';
		else
			sample_manchester_input <= 0;
		end if;
	end process;


end Behavioral;

