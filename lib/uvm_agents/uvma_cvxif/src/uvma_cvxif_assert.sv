// Copyright 2021 Thales DIS design services SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Zineb EL KACIMI (zineb.el-kacimi@external.thalesgroup.com)

/**
 * Encapsulates assertions targeting uvma_cvxif_intf.
 */
module uvma_cvxif_assert #(parameter X_ID_WIDTH    = cvxif_pkg::X_ID_WIDTH,
                           parameter X_NUM_RS      = cvxif_pkg::X_NUM_RS,
                           parameter X_RFW_WIDTH   = cvxif_pkg::X_RFW_WIDTH)
   (uvma_cvxif_intf cvxif_assert,
    input logic clk,
    input logic reset_n
   );

   import uvm_pkg::*;

   // ---------------------------------------------------------------------------
    // Local variables
   // ---------------------------------------------------------------------------
   string info_tag = "CVXIF_ASSERT";

   // Single clock, single reset design, use default clocking
   default clocking @(posedge clk); endclocking
   default disable iff !(reset_n);

   // ---------------------------------------------------------------------------
    // Begin module code
   // ---------------------------------------------------------------------------

   /**
    * Issue_interface
   */

   // Check that if a transaction is rejected, all x_issue_resp signals shall be deasserted
   property p_issue_resp_null_when_n_accept;
      (cvxif_assert.cvxif_req_i.x_issue_valid && !cvxif_assert.cvxif_resp_o.x_issue_resp.accept)
      |-> (!cvxif_assert.cvxif_resp_o.x_issue_resp.writeback && !cvxif_assert.cvxif_resp_o.x_issue_resp.dualread
        && !cvxif_assert.cvxif_resp_o.x_issue_resp.loadstore && !cvxif_assert.cvxif_resp_o.x_issue_resp.exc);
   endproperty
   a_issue_resp_null_when_n_accept:assert property (p_issue_resp_null_when_n_accept)
      else `uvm_error(info_tag, "Failure:  writeback ; dualwrite ; dualread; loadstore; exc; shall be equal to 0");
   c_issue_resp_null_when_n_accept:cover property (p_issue_resp_null_when_n_accept);

   // Check that an issue request transaction could take more than one cycle
   sequence s_issue_multic;
      cvxif_assert.cvxif_req_i.x_issue_valid ##1
      (cvxif_assert.cvxif_req_i.x_issue_valid && $stable(cvxif_assert.cvxif_req_i.x_issue_req.id));
   endsequence
   c_issue_multic: cover property(s_issue_multic);

   // Check that during an issue request transaction, the "instr" and "mode" signals should remain stable
   property p_instr_mode_stable;
      s_issue_multic |-> ($stable(cvxif_assert.cvxif_req_i.x_issue_req.instr) && $stable(cvxif_assert.cvxif_req_i.x_issue_req.mode));
   endproperty
   a_instr_mode_stable: assert property(p_instr_mode_stable);

   // Check that during an issue request transaction, each bit of "rs_valid" not allowed to transition back to 0
   property p_rs_valid(i);
      s_issue_multic |-> !($fell(cvxif_assert.cvxif_req_i.x_issue_req.rs_valid[i]));
   endproperty

   // Check that during an issue request transaction, source register "rs" should remain stable
   property p_rs_signals(i);
      s_issue_multic |-> $stable(cvxif_assert.cvxif_req_i.x_issue_req.rs[i]);
   endproperty

   always @( posedge clk) begin
      for ( int i=0;i<X_NUM_RS;i++)  begin
         if (cvxif_assert.cvxif_req_i.x_issue_req.rs_valid[i] == 1) begin
            a_rs_valid: assert property(p_rs_valid(i))
               else `uvm_error(info_tag, "Failure: rs_valid[i] is not allowed to transition back to 0 during a transaction");
            a_rs_signals: assert property(p_rs_signals(i))
               else `uvm_error(info_tag, "Failure: rs_signals shall be stable during an issue transaction");
         end
      end
   end

   /**
    * Commit_interface
   */

   //Check that "x_commit_valid" shall asserted exactly one cycle for every offloaded instruction by the co-pro (whether accepted or not)
   property p_commit_valid_pulse;
      bit [X_ID_WIDTH-1:0] id;
      (cvxif_assert.cvxif_req_i.x_commit_valid, id=cvxif_assert.cvxif_req_i.x_commit.id)
      |=> !(cvxif_assert.cvxif_req_i.x_commit_valid && cvxif_assert.cvxif_req_i.x_commit.id==id);
   endproperty
   a_commit_valid_pulse:assert property (p_commit_valid_pulse)
      else `uvm_error(info_tag, "Failure: commit_valid is asserted more than 1 cycle");
   c_commit_valid_pulse:cover property (p_commit_valid_pulse);

   //Check that a commit transaction shall be present for every transaction
   property p_issue_commit;
      bit [X_ID_WIDTH-1:0] id;
      ((cvxif_assert.cvxif_resp_o.x_issue_ready && cvxif_assert.cvxif_req_i.x_issue_valid), id=cvxif_assert.cvxif_req_i.x_issue_req.id)
      |-> (##[0:$] (cvxif_assert.cvxif_req_i.x_commit_valid && cvxif_assert.cvxif_req_i.x_commit.id==id));
   endproperty
   a_issue_commit:assert property (p_issue_commit)
      else `uvm_error(info_tag, "Failure: for every issue transaction, a commit transaction shall present ");

   //Check that a commit transaction could be present at the same clock cycle as the issue transaction
   sequence s_commit_same_cycle;
      bit [X_ID_WIDTH-1:0] id;
      ((cvxif_assert.cvxif_resp_o.x_issue_ready && cvxif_assert.cvxif_req_i.x_issue_valid), id=cvxif_assert.cvxif_req_i.x_issue_req.id)
      ##0 (cvxif_assert.cvxif_req_i.x_commit_valid && cvxif_assert.cvxif_req_i.x_commit.id==id);
   endsequence
   c_commit_same_cycle:cover property (s_commit_same_cycle);

   //Check that a commit transaction could be present, one or more clock cycle after an issue transaction
   sequence s_commit_after_n_cycle;
      bit [X_ID_WIDTH-1:0] id;
       ((cvxif_assert.cvxif_resp_o.x_issue_ready && cvxif_assert.cvxif_req_i.x_issue_valid), id=cvxif_assert.cvxif_req_i.x_issue_req.id)
      ##[1:$](cvxif_assert.cvxif_req_i.x_commit_valid && cvxif_assert.cvxif_req_i.x_commit.id==id &&
          !(cvxif_assert.cvxif_resp_o.x_issue_ready && cvxif_assert.cvxif_req_i.x_issue_valid && cvxif_assert.cvxif_req_i.x_issue_req.id==id));
   endsequence
   c_commit_after_n_cycle:cover property (s_commit_after_n_cycle);

   //For each offloaded and accepted instruction the core is guaranteed to (eventually)
   //signal that such an instruction is either no longer speculative and can be committed (commit_valid is 1 and commit_kill is 0) or
   //that the instruction must be killed (commit_valid is 1 and commit_kill is 1).
   sequence s_commit_kill;
      (cvxif_assert.cvxif_resp_o.x_issue_ready && cvxif_assert.cvxif_req_i.x_issue_valid)
      ##[0:$] ((cvxif_assert.cvxif_req_i.x_commit_valid) && (cvxif_assert.cvxif_req_i.x_commit.x_commit_kill));
   endsequence
   c_commit_kill:cover property (s_commit_kill);

   /**
    * Result_interface
   */

   //Check that "we" is 0  for synchronous exceptions ("exc" = 1).
   property p_sync_exc;
      cvxif_assert.cvxif_resp_o.x_result.exc |-> !cvxif_assert.cvxif_resp_o.x_result.we;
   endproperty
   a_sync_exc:assert property (p_sync_exc)
      else `uvm_error(info_tag, "Failure: 'we' shall be driven to 0 by the Coprocessor for synchronous exceptions");
   c_sync_exc:cover property (p_sync_exc);

   //Check proper end of result transaction
   sequence s_res_tr;
         (cvxif_assert.cvxif_resp_o.x_result_valid && cvxif_assert.cvxif_req_i.x_result_ready) ##1
          cvxif_assert.cvxif_resp_o.x_result_valid && cvxif_assert.cvxif_req_i.x_result_ready;
   endsequence

   //Check that the Id shall remain stable during a result transaction
   property p_end_res_tr;
       s_res_tr |-> $changed(cvxif_assert.cvxif_resp_o.x_result.id);
   endproperty
   a_end_res_tr: assert property (p_end_res_tr)
      else `uvm_error(info_tag, "Failure: result transaction is not ended properly");

   //sequence for result that lasts more than one cycle
   sequence s_res_multic;
      (cvxif_assert.cvxif_resp_o.x_result_valid && !cvxif_assert.cvxif_req_i.x_result_ready) ##1
      (cvxif_assert.cvxif_resp_o.x_result_valid && cvxif_assert.cvxif_req_i.x_result_ready && $stable(cvxif_assert.cvxif_resp_o.x_result.id));
   endsequence
   c_res_multic:cover property (s_res_multic);

  //Check that result signals (except data), should remain stable during a result transaction
   property p_sig_stable_res_multic;
     s_res_multic |-> $stable(cvxif_assert.cvxif_resp_o.x_result.id) && $stable(cvxif_assert.cvxif_resp_o.x_result.exc)
                   && $stable(cvxif_assert.cvxif_resp_o.x_result.rd) && $stable(cvxif_assert.cvxif_resp_o.x_result.exccode)
                   && $stable(cvxif_assert.cvxif_resp_o.x_result.we);
   endproperty
   a_sig_stable_res_multic: assert property (p_sig_stable_res_multic)
      else `uvm_error(info_tag, "Failure: result signals shall be stable during a result transaction");

   //sequence for a result transaction
   sequence s_res_multic_we;
       s_res_multic ##0 cvxif_assert.cvxif_resp_o.x_result.we;
   endsequence
   c_res_multic_we: cover property (s_res_multic_we);

   //Check that data remain stable when "we" is equal to 1
   property p_data_stable_res_multic;
       s_res_multic_we |-> $stable(cvxif_assert.cvxif_resp_o.x_result.data);
   endproperty
   a_data_stable_res_multic: assert property (p_data_stable_res_multic)
      else `uvm_error(info_tag, "Failure: data shall be stable during result transation where 'we' is asserted");

   always @(posedge clk or negedge reset_n) begin
      if (X_RFW_WIDTH!=riscv::XLEN) begin
         a_result_dualwrite: assert property (p_result_dualwrite)
            else `uvm_error(info_tag, "Failure: For dualwrite instruction, we[1]==1 is only allowed if we[0]==1");
         c_result_dualwrite: cover property  (p_result_dualwrite);
      end
   end

   //Check that for dualwrite instruction, check that we[1]==1 is only allowed if we[0] == 1.
   //Dualwrite not supported (for now)
   property p_result_dualwrite;
      (cvxif_assert.cvxif_resp_o.x_result_valid && (cvxif_assert.cvxif_resp_o.x_result.we)) |-> cvxif_assert.cvxif_resp_o.x_result.we;
   endproperty

endmodule : uvma_cvxif_assert
