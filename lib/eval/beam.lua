local constants = require 'lib.utils.constants'


local function flat_to_rc(v, flat_index)
  -- Helper function convert a `flat_index` to a row-column tuple 
  -- Where `v` is a matrix.
  -- Returns row/column.
  local row = math.floor((flat_index - 1) / v:size(2)) + 1
  return row, (flat_index - 1) % v:size(2) + 1
end

-- Class for managing the beam search process.
local Beam = torch.class('Beam')

function Beam:__init(size)
  -- Takes the beam `size`. 
  self.size = size
  self.done = false

  -- The score for each translation on the beam.
  self.scores = torch.FloatTensor(size):zero()
  
  -- The backpointers at each time-step.
  self.prev_ks = { torch.LongTensor(size):fill(1) }

  -- The outputs at each time-step. 
  self.next_ys = { torch.LongTensor(size):fill(constants.PAD) }

  -- The attentions (matrix) for each time.

  self.attn = {}
  self.next_ys[1][1] = constants.BOS
end

function Beam:get_current_state()
  -- Get the outputs for the current timestep.
  return self.next_ys[#self.next_ys]
end

function Beam:get_current_origin()
  -- Get the backpointers for the current timestep.
  return self.prev_ks[#self.prev_ks]
end

function Beam:advance(out, attn_out)
  -- Given prob over words for every last beam `out` and attention
  -- `attn_out`. Compute and update the beam search. 
  -- Returns true if beam search is complete. 

  -- The flattened scores.
  local flat_out

  if #self.prev_ks > 1 then
    -- Sum the previous scores. 
    for k = 1, self.size do
      out[k]:add(self.scores[k])
    end
    flat_out = out:view(-1)
  else
    flat_out = out[1]:view(-1)
  end


  -- Find the top-k elements in flat_out and backpointers.
  local prev_k = torch.LongTensor(self.size)
  local next_y = torch.LongTensor(self.size)
  local attn = {}

  local best_scores, best_scores_id = flat_out:topk(self.size, 1, true, true)

  for k = 1, self.size do
    self.scores[k] = best_scores[k]

    local from_beam, best_score_id = flat_to_rc(out, best_scores_id[k])

    prev_k[k] = from_beam
    next_y[k] = best_score_id
    table.insert(attn, attn_out[from_beam]:clone())
  end


  -- End condition is when top-of-beam is EOS.
  if next_y[1] == constants.EOS then
    self.done = true
  end

  table.insert(self.prev_ks, prev_k)
  table.insert(self.next_ys, next_y)
  table.insert(self.attn, attn)

  return self.done
end

function Beam:sort_best()
  return torch.sort(self.scores, 1, true)
end

function Beam:get_best()
  local scores, ids = self:sort_best()
  return scores[1], ids[1]
end

function Beam:get_hyp(k)
  -- Walk back to construct the full hypothesis `k`.
  -- Return `hyp` and the attention at each time step.
  local hyp = {}
  local attn = {}

  for _ = 1, #self.prev_ks - 1 do
    table.insert(hyp, {})
    table.insert(attn, {})
  end

  for j = #self.prev_ks, 2, -1 do
    hyp[j - 1] = self.next_ys[j][k]
    attn[j - 1] = self.attn[j - 1][k]
    k = self.prev_ks[j][k]
  end

  return hyp, attn
end

return Beam
