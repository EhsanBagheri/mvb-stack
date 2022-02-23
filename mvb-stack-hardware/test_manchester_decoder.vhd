-- Testbench for the iSim simualtion of the Manchester Decoder

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF testbench IS

	component manchester_decoder is
		Port(clk16x : in  std_logic;
			  rst : in std_logic;
			  rdn : in std_logic;
			  manchester_in : in  std_logic;
			  decoded_out : out  std_logic_vector(7 downto 0);		
			  data_ready : out	std_logic
			  );
	end component manchester_decoder;
	
	signal clk : std_logic;
	signal rst : std_logic;
	signal rdn : std_logic;
	signal manchester_in : std_logic;
	signal decoded_out : std_logic_vector(7 downto 0);
	signal data_ready : std_logic;
	
	
BEGIN


-- Component Instantiation
		 tested_decoder: manchester_decoder PORT MAP(
					clk16x => clk,
					rst => rst,
					rdn => rdn,
					manchester_in => manchester_in,
					decoded_out => decoded_out,
					data_ready => data_ready
		 );


	--  Test Bench Statements
	tb : PROCESS
	BEGIN
		-- Reset and Clock
		rst <= '1', '0' after 100 ns;
		clk <= not clk after 5 ns;

		-- Test stimulus
		

		wait; -- will wait forever
	END PROCESS tb;
--  End Test Bench 

END;
