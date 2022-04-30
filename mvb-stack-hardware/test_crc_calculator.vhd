-- TestBench for the CRC generator

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
 
ENTITY test_crc_calculator IS
END test_crc_calculator;
 
ARCHITECTURE behavior OF test_crc_calculator IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT e_CRC_CALCULATOR
    PORT(
         clk : IN  std_logic;
         rst : IN  std_logic;
         start_calculation : IN  std_logic;
         read_input : IN  std_logic;
         serial_input : IN  std_logic;
         awaited_ipnut_length : IN  std_logic_vector(6 downto 0);
         crc_output : OUT  std_logic_vector(7 downto 0)
        );
    END COMPONENT;
	 
	constant input_length_16 : std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(16, 7));
	constant input_length_32 : std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(32, 7));
	constant input_length_64 : std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(64, 7));
	
	constant dummy_message_16 : std_logic_vector(16 downto 0) := "00101010101010101";--"0011001111001100"; --"1100001101111110";
	constant dummy_message_32 : std_logic_vector(31 downto 0) := "10101010110011001010101011001100";
	constant dummy_message_64 : std_logic_vector(63 downto 0) := "1010101011001100101010101100110010101010110011001010101011001100";
	
	-- assistance
	signal input_sync_counter : unsigned(7 downto 0);
   signal i : integer := 0;

   --Inputs
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal start_calculation : std_logic := '0';
   signal read_input : std_logic := '0';
   signal serial_input : std_logic := '0';
   signal awaited_ipnut_length : std_logic_vector(6 downto 0) := (others => '0');

 	--Outputs
   signal crc_output : std_logic_vector(7 downto 0);

   -- Clock period definitions
   constant clk_period : time := 4 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   tested_calculator : e_CRC_CALCULATOR PORT MAP (
          clk => clk,
          rst => rst,
          start_calculation => start_calculation,
          read_input => read_input,
          serial_input => serial_input,
          awaited_ipnut_length => awaited_ipnut_length,
          crc_output => crc_output
        );
		  
	-- count a sending period, because it didin't work with a wait statement
	sending_sync : process (clk)
	begin
		if(rising_edge(clk)) then
			if((input_sync_counter = to_unsigned(50, 8)) or (rst = '1')) then 
				input_sync_counter <= to_unsigned(0, 8);
				
			elsif(input_sync_counter = to_unsigned(25, 8)) then
				input_sync_counter <= input_sync_counter + 1;
				read_input <= '1';
				
			else 
				input_sync_counter <= input_sync_counter + 1;
				read_input <= '0';
				
			end if;
		end if;
	end process sending_sync;
		  
	-- generate serial input
	manchester_gen : process (clk)
	begin
		if(rst = '0') then
				if(rising_edge(clk) and (input_sync_counter = to_unsigned(0, 8))) then
					serial_input <= dummy_message_16(i);
					i <= i + 1;
				end if;
				if(i = 16) then i <= 0; end if;
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
	
		-- test calculation for 16 bit message
		awaited_ipnut_length <= input_length_16;
		
      -- hold reset state for 100 ns.
      wait for 100 ns;
		start_calculation <= '1';
		rst <= '0';
		
		wait for clk_period;
		start_calculation <= '0';
		
      wait for clk_period*10;
		

		
      
      wait;
   end process;

END;
