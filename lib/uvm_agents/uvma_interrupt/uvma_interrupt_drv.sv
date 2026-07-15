//
// Copyright 2020 OpenHW Group
// Copyright 2020 Datum Technology Corporation
// Copyright 2020 Silicon Labs, Inc.
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

`ifndef __UVMA_INTERRUPT_DRV_SV__
`define __UVMA_INTERRUPT_DRV_SV__

/**
 * Component driving a Clock & Reset virtual interface (uvma_interrupt_if).
 */
class uvma_interrupt_drv_c extends uvm_driver#(
   .REQ(uvma_interrupt_seq_item_c),
   .RSP(uvma_interrupt_seq_item_c)
);

   // Objects
   uvma_interrupt_cfg_c    cfg;
   uvma_interrupt_cntxt_c  cntxt;

   semaphore               assert_until_ack_sem[32];

   // Serializes the actual irq_drv[] rising edge across all 32 lines (not just same-index, unlike
   // assert_until_ack_sem above): only one new edge is allowed at a time, and the holder keeps the
   // lock for 2 extra cycles after driving it, so any two new rising edges are guaranteed to land
   // on different clock edges and be at least 2 cycles apart. Deliberately does NOT gate on
   // cntxt.vif.drv_cb.id_in_ready (the core's id_in_ready_o): id_in_ready_o stays low while the
   // core is parked in WFI, so waiting on it here would block forever on the very interrupt meant
   // to wake it.
   semaphore               new_irq_edge_sem;

   // TLM
   uvm_analysis_port#(uvma_interrupt_seq_item_c)  ap;

   `uvm_component_utils_begin(uvma_interrupt_drv_c)
      `uvm_field_object(cfg  , UVM_DEFAULT)
      `uvm_field_object(cntxt, UVM_DEFAULT)
   `uvm_component_utils_end

   /**
    * Default constructor.
    */
   extern function new(string name="uvma_interrupt_drv", uvm_component parent=null);

   /**
    * 1. Ensures cfg & cntxt handles are not null.
    * 2. Builds ap.
    */
   extern virtual function void build_phase(uvm_phase phase);

   /**
    * Obtains the reqs from the sequence item port and calls drv_req()
    */
   extern virtual task run_phase(uvm_phase phase);

   /**
    * Thread that clears acknowledged interrupts that were randomly asserted
    */
   extern task irq_ack_clear();

   /**
    * Drives the virtual interface's (cntxt.vif) signals using req's contents.
    */
   extern task drv_req(uvma_interrupt_seq_item_c req);

   /**
    * Waits for new_irq_edge_sem and cntxt.vif.drv_cb.id_in_ready, then drives irq_drv[index] high
    * and holds the lock a couple more cycles so id_in_ready has time to respond before the next
    * waiting caller re-checks it.
    */
   extern task wait_and_assert_irq_edge(int unsigned index);

   /**
    * Forked thread to handle interrupts
    */
   extern task assert_irq_until_ack(int unsigned index, int unsigned repeat_count, int unsigned skew);

   /**
    * Assert an interrupt signal
    */
   extern task assert_irq(int unsigned index, int unsigned skew);

   /**
    * Deassert an interrupt signal
    */
   extern task deassert_irq(int unsigned index, int unsigned skew);

endclass : uvma_interrupt_drv_c

function uvma_interrupt_drv_c::new(string name="uvma_interrupt_drv", uvm_component parent=null);

   super.new(name, parent);

endfunction : new


function void uvma_interrupt_drv_c::build_phase(uvm_phase phase);

   super.build_phase(phase);

   void'(uvm_config_db#(uvma_interrupt_cfg_c)::get(this, "", "cfg", cfg));
   if (cfg == null) begin
      `uvm_fatal("CFG", "Configuration handle is null")
   end
   uvm_config_db#(uvma_interrupt_cfg_c)::set(this, "*", "cfg", cfg);

   void'(uvm_config_db#(uvma_interrupt_cntxt_c)::get(this, "", "cntxt", cntxt));
   if (cntxt == null) begin
      `uvm_fatal("CNTXT", "Context handle is null")
   end
   uvm_config_db#(uvma_interrupt_cntxt_c)::set(this, "*", "cntxt", cntxt);

   ap = new("ap", this);

   foreach (assert_until_ack_sem[i]) begin
      assert_until_ack_sem[i] = new(1);
   end

   new_irq_edge_sem = new(1);
endfunction : build_phase


task uvma_interrupt_drv_c::run_phase(uvm_phase phase);

   super.run_phase(phase);

   // Enable the driver in the interface
   cntxt.vif.is_active = 1;

   // Fork thread to deassert randomly asserted interrupts when acknowledged
   fork
      irq_ack_clear();
   join_none

   forever begin
      seq_item_port.get_next_item(req);
      `uvml_hrtbt()
      drv_req(req);
      ap.write(req);
      seq_item_port.item_done();
   end

endtask : run_phase

task uvma_interrupt_drv_c::drv_req(uvma_interrupt_seq_item_c req);
   `uvm_info("INTERRUPTDRV", $sformatf("Driving:\n%s", req.sprint()), UVM_HIGH);
   case (req.action)
      UVMA_INTERRUPT_SEQ_ITEM_ACTION_ASSERT_UNTIL_ACK: begin
         for (int i = 0; i < 32; i++) begin
            if (req.irq_mask[i]) begin
               automatic int ii = i;
               fork
                  assert_irq_until_ack(ii, req.repeat_count, req.skew[ii]);
               join_none
            end
         end
      end
      UVMA_INTERRUPT_SEQ_ITEM_ACTION_ASSERT: begin
         for (int i = 0; i < 32; i++) begin
            if (req.irq_mask[i]) begin
               automatic int ii = i;
               fork
                  assert_irq(ii, req.skew[ii]);
               join_none
            end
         end
      end
      UVMA_INTERRUPT_SEQ_ITEM_ACTION_DEASSERT: begin
         for (int i = 0; i < 32; i++) begin
            if (req.irq_mask[i]) begin
               automatic int ii = i;
               fork
                  deassert_irq(ii, req.skew[ii]);
               join_none
            end
         end
      end
   endcase

endtask : drv_req

task uvma_interrupt_drv_c::wait_and_assert_irq_edge(int unsigned index);
   new_irq_edge_sem.get(1);
   // Previously also waited on cntxt.vif.drv_cb.id_in_ready here (the core's id_in_ready_o) before
   // driving the edge, to avoid racing an in-flight exception request. Reverted: that wait can
   // deadlock outright when the core is genuinely parked in WFI (id_in_ready_o stays low while
   // asleep), since it then blocks forever waiting to "be ready" for the very interrupt that would
   // wake it. The actual false-assertion hazard it was defending against
   // (CVE2DontSkipExceptionReq/CVE2SetExceptionPCOnSpecialReqIfExpected on a withdrawn-but-still-
   // latched request) is now fixed at its root in cve2_controller.sv (exception_req_withdrawn), so
   // this driver-side gate is redundant as well as harmful. See
   // E20DV/tmp/exception_req_pending_finding.md.
   cntxt.vif.drv_cb.irq_drv[index] <= 1'b1;
   repeat (2) @(cntxt.vif.drv_cb);
   new_irq_edge_sem.put(1);
endtask : wait_and_assert_irq_edge

task uvma_interrupt_drv_c::assert_irq_until_ack(int unsigned index, int unsigned repeat_count, int unsigned skew);
   // If a thread is already running on this irq, then exit
   if (!assert_until_ack_sem[index].try_get(1))
      return;

   repeat (skew) @(cntxt.vif.drv_cb);

   for (int loop = 0; loop < repeat_count; loop++) begin
      repeat (skew) @(cntxt.vif.drv_cb);
      wait_and_assert_irq_edge(index);

      while (1) begin
         @(cntxt.vif.mon_cb);
         if ((cntxt.vif.mon_cb.irq_ack && cntxt.vif.mon_cb.irq_id == index))
            break;
      end
   end

   `uvm_info("IRQDRV", $sformatf("assert_irq_until_ack: Deasserting irq: %0d", index), UVM_DEBUG);
   cntxt.vif.drv_cb.irq_drv[index] <= 1'b0;
   assert_until_ack_sem[index].put(1);
endtask : assert_irq_until_ack

task uvma_interrupt_drv_c::assert_irq(int unsigned index, int unsigned skew);
   if (assert_until_ack_sem[index].try_get(1)) begin
      repeat (skew) @(cntxt.vif.drv_cb);
      wait_and_assert_irq_edge(index);
      assert_until_ack_sem[index].put(1);
      return;
   end

   wait_and_assert_irq_edge(index);
endtask : assert_irq

task uvma_interrupt_drv_c::deassert_irq(int unsigned index, int unsigned skew);
   if (assert_until_ack_sem[index].try_get(1)) begin
      repeat (skew) @(cntxt.vif.drv_cb);
      cntxt.vif.drv_cb.irq_drv[index] <= 1'b0;
      assert_until_ack_sem[index].put(1);
      return;
   end
endtask : deassert_irq

task uvma_interrupt_drv_c::irq_ack_clear();
   while(1) begin
      @(cntxt.vif.mon_cb);
      if (cntxt.vif.mon_cb.irq_ack) begin
         // Try to get the semaphore for the irq_id,
         // If we can't get it, then this irq is managed by assert_irq_until_ack and we will ignore this ack
         // Otherwise deassert the interrupt
         int unsigned irq_id;

         irq_id  = cntxt.vif.mon_cb.irq_id;

         `uvm_info("IRQDRV", $sformatf("irq_ack_clear: ack for IRQ: %0d", irq_id), UVM_DEBUG);
         if (assert_until_ack_sem[irq_id].try_get(1)) begin
            `uvm_info("IRQDRV", $sformatf("irq_ack_clear: Clearing IRQ: %0d", irq_id), UVM_DEBUG);
            cntxt.vif.drv_cb.irq_drv[irq_id] <= 1'b0;
            assert_until_ack_sem[irq_id].put(1);
         end
      end
   end
endtask

`endif // __UVMA_INTERRUPT_DRV_SV__
