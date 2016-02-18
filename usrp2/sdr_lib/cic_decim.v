// -*- verilog -*-
//
//  USRP - Universal Software Radio Peripheral
//
//  Copyright (C) 2003 Matt Ettus
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Boston, MA  02110-1301  USA
//


module cic_decim
  #(parameter bw = 16, parameter N = 4, parameter log2_of_max_rate = 7)
    (input clock,
     input reset,
     input enable,
     input [7:0] rate,
     input [2:0] gain_bits,
     input strobe_in,
     input strobe_out,
     input [bw-1:0] signal_in,
     output reg [bw-1:0] signal_out);

   localparam 	     maxbitgain = N * log2_of_max_rate;
   
   wire [bw+maxbitgain-1:0] signal_in_ext;
   reg [bw+maxbitgain-1:0]  integrator [0:N-1];
   reg [bw+maxbitgain-1:0]  differentiator [0:N-1];
   reg [bw+maxbitgain-1:0]  pipeline [0:N-1];
   reg [bw+maxbitgain-1:0]  sampler;
   
   integer 		    i;
   
   sign_extend #(bw,bw+maxbitgain) 
     ext_input (.in(signal_in),.out(signal_in_ext));
   
   always @(posedge clock)
     if(~enable)
       for(i=0;i<N;i=i+1)
	 integrator[i] <= 0;
     else if (strobe_in)
       begin
	  integrator[0] <= integrator[0] + signal_in_ext;
	  for(i=1;i<N;i=i+1)
	    integrator[i] <= integrator[i] + integrator[i-1];
       end	
   
   always @(posedge clock)
     if(~enable)
       begin
	  sampler <= 0;
	  for(i=0;i<N;i=i+1)
	    begin
	       pipeline[i] <= 0;
	       differentiator[i] <= 0;
	    end
       end
     else if (strobe_out)
       begin
	  sampler <= integrator[N-1];
	  differentiator[0] <= sampler;
	  pipeline[0] <= sampler - differentiator[0];
	  for(i=1;i<N;i=i+1)
	    begin
	       differentiator[i] <= pipeline[i-1];
	       pipeline[i] <= pipeline[i-1] - differentiator[i];
	    end
       end // if (enable && strobe_out)

   // pad to allow for added gain when shift from decimation is small
   localparam gainwidth = 3;
   localparam padbits = 2**gainwidth-1;
   localparam paddedbw = bw + maxbitgain + padbits;

   wire [paddedbw-1:0] signal_pad = {pipeline[N-1], {padbits{1'b0}}};
   wire [bw+padbits-1:0] signal_shifted;

   cic_dec_shifter #(bw+padbits)
     cic_dec_shifter(clock,rate,signal_pad,signal_shifted);

   // use register for gainidx to limit delay
   reg [gainwidth-1:0] gainidx;
   always @(posedge clock)
     gainidx <= padbits - gain_bits;

   wire [bw-1:0] signal_out_unreg;

   // apply variable gain by selecting appropriate part of signal_shifted and clipping
   variable_part_select_and_clip #(.WIDTH_IN(bw+padbits),.WIDTH_OUT(bw),.INDEX_WIDTH(gainwidth))
     vargain(.clk(clock),.signal_in(signal_shifted),.lowidx(gainidx),.signal_out(signal_out_unreg));

   always @(posedge clock)
     signal_out <= signal_out_unreg;
   
endmodule // cic_decim
