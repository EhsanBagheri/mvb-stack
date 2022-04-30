
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY test_crc IS
END test_crc;
 
ARCHITECTURE behavior OF test_crc IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT e_CRC
    PORT(
         clk : IN  std_logic;
         rst : IN  std_logic;
         wr : IN  std_logic;
         serial_in : IN  std_logic;
         shift_zeroes : IN  std_logic;
         rdy : OUT  std_logic;
         crc_out : OUT  std_logic_vector(7 downto 0)
        );
    END COMPONENT;
    

   --Inputs
   signal clk : std_logic := '0';
   signal rst : std_logic := '0';
   signal wr : std_logic := '0';
   signal serial_in : std_logic := '0';
   signal shift_zeroes : std_logic := '0';

 	--Outputs
   signal rdy : std_logic;
   signal crc_out : std_logic_vector(7 downto 0);

   -- Clock period definitions
   constant clk_period : time := 10 ns;
	
	-- test constants
	constant dummy_message_16 : std_logic_vector(17 downto 0) := "001010101010101010";--"0011001111001100"; --"1100001101111110";
	constant dummy_message_32 : std_logic_vector(33 downto 0) := "0010101010110011001010101011001100";
	constant dummy_message_64 : std_logic_vector(63 downto 0) := "1010101011001100101010101100110010101010110011001010101011001100";
	
	-- input synchronization
	signal input_sync_counter : unsigned(7 downto 0);
	signal i : integer := 0;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   tested_crc : e_CRC PORT MAP (
          clk => clk,
          rst => rst,
          wr => wr,
          serial_in => serial_in,
          shift_zeroes => shift_zeroes,
          rdy => rdy,
          crc_out => crc_out
        );
		  
		  
	sending_sync : process (clk)
	begin
		if(rising_edge(clk)) then
			if((input_sync_counter = to_unsigned(50, 8)) or (rst = '1')) then 
				input_sync_counter <= to_unsigned(0, 8);
				
			elsif(input_sync_counter = to_unsigned(25, 8)) then
				input_sync_counter <= input_sync_counter + 1;
				wr <= '1';
				
			else 
				input_sync_counter <= input_sync_counter + 1;
				wr <= '0';
				
			end if;
		end if;
	end process sending_sync;
		  
	-- generate serial input
	manchester_gen : process (clk)
	begin
		if(rst = '0') then
				if(rising_edge(clk) and (input_sync_counter = to_unsigned(0, 8))) then
					serial_in <= dummy_message_32(i);
					i <= i + 1;
				end if;
				if(i = 33) then i <= 0; shift_zeroes <= '1'; end if;
		end if;
	end process manchester_gen;

   -- Clock process definitions
   clk_process :process
   begin
		clk <= '0';
		wait for clk_period/2;
		clk <= '1';
		wait for clk_period/2;
   end process;
 

   -- Stimulus process
   stim_proc: process
   begin		
		rst <= '1';
      wait for 100 ns;	
		rst <= '0';
      wait for clk_period*10;

      wait;
   end process;

END;
