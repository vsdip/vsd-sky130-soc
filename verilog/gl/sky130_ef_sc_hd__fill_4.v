// Compatibility shim for GL simulation: some Caravel GL netlists
// instantiate sky130_ef_sc_hd__fill_4 while the available digital
// library model is sky130_fd_sc_hd__fill_4.

`default_nettype none
module sky130_ef_sc_hd__fill_4 (
`ifdef USE_POWER_PINS
    inout VGND,
    inout VNB,
    inout VPB,
    inout VPWR
`endif
);
    sky130_fd_sc_hd__fill_4 u_fill (
`ifdef USE_POWER_PINS
        .VGND(VGND),
        .VNB(VNB),
        .VPB(VPB),
        .VPWR(VPWR)
`endif
    );
endmodule
`default_nettype wire
