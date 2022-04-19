
-- Testbench for the iSim simualtion of the Manchester Decoder

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;

ENTITY test_manchester_decoder IS
END test_manchester_decoder;

ARCHITECTURE behavior OF test_manchester_decoder IS

	component e_MANCHESTER_DECODER is
		Port(clk : in  		std_logic;
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
	-- 01011010010110100101101010100101 -- random 16 bit manchester code
	-- constant test_manchester_code : std_logic_vector(49 downto 0) := "00000000000000001100011100010101010000000000000000";	--slave delim
	-- constant test_manchester_code : std_logic_vector(49 downto 0) := "00000000000000001010100011100011010000000000000000";	--master delim
	
	signal i : integer := 0;
	
	signal clk : std_logic := '0';
	signal rst : std_logic := '0';
	signal rdn : std_logic := '0';
	signal manchester_in : std_logic := '0';
	signal decoded_out : std_logic_vector(15 downto 0) := "0000000000000000";
	signal data_ready : std_logic := '0';
	signal input_sync_counter : unsigned(7 downto 0) := to_unsigned(0, 8);
	
	signal master_frame : std_logic_vector(67 downto 0);	-- start bit: 2 | start delim: 18 | data: 32 | crc: 16 | end delim: 2
	signal slave_frame : std_logic_vector(309 downto 0);
	
	signal test_manchester_code : std_logic_vector(401 downto 0); 
	
	
BEGIN

-- Get Slave and Master Delimiter test vectors from file (already manchester coded in the file)
	--get_test_master_frame : process is
	--	variable line_v : line;
		
	--	file master_file : text;
	--	file slave_file : text;
		
	--	variable master_frame_var : std_logic_vector(67 downto 0);
		--variable slave_frame_var : std_logic_vector(309 downto 0);
		
	--begin
	--	file_open(master_file, "master_frame.txt", read_mode);
	--	readline(master_file, line_v);
	--	read(line_v, master_frame_var);
	--	master_frame <= master_frame_var;
	--	file_close(master_file);
		
		--file_open(slave_file, "slave_frame.txt", read_mode);
		--readline(slave_file, line_v);
		--read(line_v, slave_frame_var);
		--slave_frame <= slave_frame_var;
		--file_close(slave_file);
		
	--	wait;
	--end process get_test_master_frame;
	master_frame <= "00000000110101101001011010010110101010010110101000111000110100000000";
	slave_frame <= "1110101010010101011010010110100101101001011010010110100101101001011010010110100101101001011010010110100101101001011010010110100101101001011010010110101010010101010101101001011010010110100101101001011010010110100101101001011010010110100101101001011010010110100101101001011010010110100101101011000111000101010100";

	
	test_manchester_code <= "00000000" & slave_frame & "00000000" & master_frame & "00000000";


-- Component Instantiation
		 tested_decoder: e_MANCHESTER_DECODER PORT MAP(
					clk => clk,
					rst => rst,
					rdn => rdn,
					manchester_in => manchester_in,
					decoded_out => decoded_out,
					data_ready => data_ready
		 );
		 
	-- Generate clock signal
	clk_gen : process
	begin
		clk <= '0';
		wait for clk_period/2;
		clk <= '1';
		wait for clk_period/2;
	end process clk_gen;
	
	-- count a sending period, because it didin't work with a wait statement
	sending_sync : process (clk)
	begin
		if(rising_edge(clk)) then
			if((input_sync_counter = to_unsigned(50, 8)) or (rst = '1')) then input_sync_counter <= to_unsigned(0, 8);
			else input_sync_counter <= input_sync_counter + 1;
			end if;
		end if;
	end process sending_sync;
	
	-- Generate manchester coded serial input
	manchester_gen : process (clk)
	begin
		if(rst = '0') then
				if(rising_edge(clk) and (input_sync_counter = to_unsigned(0, 8))) then
					manchester_in <= test_manchester_code(i);
					i <= i + 1;
				end if;
				if(i = 401) then i <= 0; end if;
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
