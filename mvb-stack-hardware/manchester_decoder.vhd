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

-- create internal registers for edge detection:
signal man_data_in1 : std_logic;
signal man_data_in2 : std_logic;

-- controls word size and sequences decoder through operations
signal no_bits_recieved : std_logic;

-- internal 1x clock signal and clock enable
signal clk1x : std_logic;
signal clk1x_en : std_logic;

-- when is the reciever to decode data?
signal sampe : std_logic;

-- variable used by the counter to determine end count
signal first : std_logic;

begin



end Behavioral;

