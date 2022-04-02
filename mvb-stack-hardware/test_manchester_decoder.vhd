
-- Testbench for the iSim simualtion of the Manchester Decoder

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF test_manchester_decoder IS

	component e_MANCHESTER_DECODER is
		Port(clk_xx : in  		std_logic;
			  rst : in 				std_logic;
			  rdn : in 				std_logic;
			  manchester_in : in	std_logic;
			  decoded_out : out  std_logic_vector(15 downto 0);		
			  data_ready : out	std_logic
			  );
	end component e_MANCHESTER_DECODER;
	
	constant clk_period : time := 10 ns;
	-- Random test constant from the internet 10100111001 (for now)
	-- constant test_manchester_code : std_logic_vector(21 downto 0) := "1001100101101010010110";	--random manchester code
	-- constant test_manchester_code : std_logic_vector(49 downto 0) := "00000000000000001100011100010101010000000000000000";	--slave delim
	-- constant test_manchester_code : std_logic_vector(49 downto 0) := "00000000000000001010100011100011010000000000000000";	-- master delim
	constant test_manchester_code : std_logic_vector(93 downto 0) := "0000000011001010101010101010010110100101101001011010010110101010100011100011010000000000000000";	
	signal i : integer := 0;
	
	signal clk_xx : std_logic := '0';
	signal rst : std_logic := '0';
	signal rdn : std_logic := '0';
	signal manchester_in : std_logic := '0';
	signal decoded_out : std_logic_vector(15 downto 0) := "0000000000000000";
	signal data_ready : std_logic := '0';
	signal input_sync_counter : unsigned(7 downto 0) := to_unsigned(0, 8);
	
	
BEGIN


-- Component Instantiation
		 tested_decoder: e_MANCHESTER_DECODER PORT MAP(
					clk_xx => clk_xx,
					rst => rst,
					rdn => rdn,
					manchester_in => manchester_in,
					decoded_out => decoded_out,
					data_ready => data_ready
		 );
		 
	-- Generate clock signal
	clk_gen : process
	begin
		clk_xx <= '0';
		wait for clk_period/2;
		clk_xx <= '1';
		wait for clk_period/2;
	end process clk_gen;
	
	-- count a sending period, because it didin't work with a wait statement
	sending_sync : process (clk_xx)
	begin
		if(rising_edge(clk_xx)) then
			if((input_sync_counter = to_unsigned(50, 8)) or (rst = '1')) then input_sync_counter <= to_unsigned(0, 8);
			else input_sync_counter <= input_sync_counter + 1;
			end if;
		end if;
	end process sending_sync;
	
	-- Generate manchester coded serial input
	manchester_gen : process (clk_xx)
	begin
		if(rst = '0') then
				if(rising_edge(clk_xx) and (input_sync_counter = to_unsigned(0, 8))) then
					manchester_in <= test_manchester_code(i);
					i <= i + 1;
				end if;
				if(i = 93) then i <= 0; end if;
		end if;
	end process manchester_gen;


	--  Test Bench Statements
	tb : PROCESS
	BEGIN
		-- Manual reset
		rst <= '1', '0' after 100 ns;


		wait; -- will wait forever
	END PROCESS tb;
--  End Test Bench 

END behavior;
