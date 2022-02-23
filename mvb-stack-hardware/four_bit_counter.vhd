-- Extremely simple four-bit counter that counts every
--		clock-cycle, and is resetable to zero.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity four_bit_counter is
    Port ( rst,clk,up_dwn : in std_logic;
           output: out std_logic_vector(0 to 3));
end four_bit_counter;

architecture four_bit_counter_arch of four_bit_counter is
   signal count : std_logic_vector(0 to 3);
    begin
      process(rst,clk)
        begin
          if (rst = '1') then count <= "0000";
          elsif (clk'event and clk = '0') then
           if (up_dwn = '1') then count <= count - 1;
           else   count <= count + 1;
          end if;
         end if;
         end process;
         output <= count;
      end four_bit_counter_arch;