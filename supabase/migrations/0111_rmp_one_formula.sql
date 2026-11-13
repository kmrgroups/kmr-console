-- One formula for the Work sheet and the Raw material plan: the Excel super-market (RRS) level becomes part of the
-- minimum stock level and the second WIP stage is added into WIP stock. Runs once per row (the old fields are zeroed).
update console.rmp_partstock
   set safety_qty = safety_qty + rrs_qty, rrs_qty = 0,
       wip_qty = wip_qty + wip2_qty, wip2_qty = 0
 where rrs_qty <> 0 or wip2_qty <> 0;
