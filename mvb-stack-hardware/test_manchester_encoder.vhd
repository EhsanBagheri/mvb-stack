-- manchester encoder test bench for the Multifunction Vehicle Bus
-- BME MIT

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY test_manchester_encoder IS
END test_manchester_encoder;
 
ARCHITECTURE behavior OF test_manchester_encoder IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT e_MANCHESTER_ENCODER
    PORT(
         clk : IN  std_logic;
         rst : IN  std_logic;
         start_transmission : IN  std_logic;
         data_length : IN  std_logic_vector(4 downto 0);
         frame_type : in std_logic;
         din : IN  std_logic_vector(7 downto 0);
         wr_en : IN  std_logic;
         encoded_out : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal start_transmission : std_logic := '0';
   signal data_length : std_logic_vector(4 downto 0);
   signal frame_type : std_logic := '0';
   signal din : std_logic_vector(7 downto 0) := (others => '0');
   signal wr_en : std_logic := '0';

 	--Outputs
   signal encoded_out : std_logic;

   -- Clock period definitions
   constant clk_period : time := 10 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   tested_encoder : e_MANCHESTER_ENCODER PORT MAP (
          clk => clk,
          rst => rst,
          start_transmission => start_transmission,
          data_length => data_length,
          frame_type => frame_type,
          din => din,
          wr_en => wr_en,
          encoded_out => encoded_out
        );

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
      -- hold reset state for 100 ns.
      wait for 100 ns;
		
		rst <= '0';

		-- load fifo
      wait for clk_period*10;
        wr_en <= '1';
		din <= "10101010";
		wait for clk_period;	
		din <= "11001100";		
		wait for clk_period;		
		wr_en <= '0';
		
		-- start transmission
		wait for clk_period*10;
		data_length <= std_logic_vector(to_unsigned(1, 5));
		wait for clk_period;
		start_transmission <= '1';
		wait for clk_period;
		start_transmission <= '0';

-- TEST AGAIN
		-- load fifo
        wait for 15000 ns;
        wr_en <= '1';
		din <= "10101010";
		wait for clk_period;	
		din <= "11001100";		
		wait for clk_period;		
		wr_en <= '0';
		
		-- start transmission
		wait for clk_period*10;
		data_length <= std_logic_vector(to_unsigned(1, 5));
		wait for clk_period;
		start_transmission <= '1';
		wait for clk_period;
		start_transmission <= '0';
		
-- TEST FOR LONGER MESSAGE
		-- load fifo
        wait for 15000 ns;
        wr_en <= '1';
		din <= "10101010";
		wait for clk_period;	
		din <= "11001100";		
		wait for clk_period;
		din <= "11111111";
		wait for clk_period;	
		din <= "00000000";		
		wait for clk_period;	
		din <= "10101010";
		wait for clk_period;	
		din <= "11001100";
		wait for clk_period;
		din <= "11111111";
		wait for clk_period;	
		din <= "00000000";		
		wait for clk_period;
		din <= "10101010";
		wait for clk_period;	
		din <= "11001100";		
		wait for clk_period;
		din <= "11111111";
		wait for clk_period;	
		din <= "00000000";		
		wait for clk_period;	
		din <= "10101010";
		wait for clk_period;	
		din <= "11001100";
		wait for clk_period;
		din <= "11111111";
		wait for clk_period;	
		din <= "00000000";		
		wait for clk_period;
		wr_en <= '0';
		
		-- start transmission
		wait for clk_period*10;
		data_length <= std_logic_vector(to_unsigned(8, 5));
		wait for clk_period;
		start_transmission <= '1';
		wait for clk_period;
		start_transmission <= '0';

      wait;
   end process;

END;
