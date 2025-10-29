-- {"query": "217.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2903}
with
recent_posts as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.ClosedDate,
    coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName) as OwnerName
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
post_tags as (
  select
    rp.PostId,
    lower(unnest(string_to_array(substring(rp.Tags from 2 for length(rp.Tags)-2), '><'))) as tag
  from recent_posts rp
  where rp.PostTypeId = 1
    and rp.Tags is not null
),
tag_stats as (
  select
    pt.tag,
    count(*) as tag_q_count,
    sum(case when rp.Score > 0 then 1 else 0 end) as tag_q_pos,
    avg(cast(rp.Score as numeric)) as avg_q_score,
    percentile_cont(0.5) within group (order by rp.Score) as med_q_score
  from post_tags pt
  join recent_posts rp on rp.PostId = pt.PostId
  group by pt.tag
),
vote_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_total,
    min(v.CreationDate) filter (where v.VoteTypeId = 2) as first_upvote_at
  from Votes v
  group by v.PostId
),
comment_agg as (
  select
    c.PostId,
    count(*) as comment_count,
    sum(case when c.Score > 0 then 1 else 0 end) as pos_comment_count,
    max(c.CreationDate) as last_comment_at
  from Comments c
  group by c.PostId
),
history_flags as (
  select
    ph.PostId,
    sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as close_votes,
    sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as reopen_votes,
    sum(case when ph.PostHistoryTypeId in (4,5,6,24) then 1 else 0 end) as edit_events,
    max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) end) as last_close_reason_id
  from PostHistory ph
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 3) as duplicate_of_count,
    count(*) filter (where pl.LinkTypeId = 1) as linked_count,
    min(pl.CreationDate) filter (where pl.LinkTypeId = 3) as first_dup_link_at
  from PostLinks pl
  group by pl.PostId
),
user_profile as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreated,
    u.Views as UserViews,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as Location,
    sum(case when p.PostTypeId = 1 then 1 else 0 end) as total_questions,
    sum(case when p.PostTypeId = 2 then 1 else 0 end) as total_answers,
    avg(nullif(p.Score,0)) as avg_nonzero_post_score,
    count(distinct date_trunc('day', p.CreationDate)) as active_days
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, u.Location
),
badge_tiers as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.TagBased = true then 1 else 0 end) as tag_badges
  from Badges b
  group by b.UserId
),
post_signals as (
  select
    rp.PostId,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CreationDate,
    rp.Title,
    dense_rank() over (order by coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc, rp.Score desc, rp.ViewCount desc) as engagement_rank,
    row_number() over (partition by rp.OwnerUserId order by rp.CreationDate desc, rp.Score desc) as recency_rank_for_user,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.pos_comment_count,0) as pos_comment_count,
    va.first_upvote_at,
    ca.last_comment_at,
    coalesce(hf.close_votes,0) as close_votes,
    coalesce(hf.reopen_votes,0) as reopen_votes,
    coalesce(hf.edit_events,0) as edit_events,
    hf.last_close_reason_id,
    coalesce(dl.duplicate_of_count,0) as duplicate_of_count,
    coalesce(dl.linked_count,0) as linked_count,
    dl.first_dup_link_at
  from recent_posts rp
  left join vote_agg va on va.PostId = rp.PostId
  left join comment_agg ca on ca.PostId = rp.PostId
  left join history_flags hf on hf.PostId = rp.PostId
  left join dup_links dl on dl.PostId = rp.PostId
),
post_scores as (
  select
    ps.*,
    (
      0.4 * ln(1 + greatest(ps.upvotes - ps.downvotes, 0)) +
      0.25 * ln(1 + coalesce(ps.ViewCount,0)) +
      0.2 * coalesce(ps.AnswerCount,0) +
      0.1 * ln(1 + coalesce(ps.favorites,0)) +
      0.15 * ln(1 + coalesce(ps.bounty_total,0)) +
      0.05 * ln(1 + coalesce(ps.comment_count,0)) -
      0.3 * ln(1 + coalesce(ps.close_votes,0)) -
      0.2 * ln(1 + coalesce(ps.duplicate_of_count,0))
    ) as composite_score
  from post_signals ps
),
controversial as (
  select
    PostId,
    case
      when comment_count >= 10 and (upvotes + downvotes) >= 5 and abs(upvotes - downvotes) <= 2
      then 1 else 0 end as is_controversial
  from post_signals
),
post_tag_enrichment as (
  select
    pt.PostId,
    array_agg(distinct pt.tag order by pt.tag) as tags,
    avg(ts.avg_q_score) as tag_avg_q_score,
    max(ts.med_q_score) as tag_med_q_score,
    sum(ts.tag_q_pos) as tag_q_pos_sum,
    sum(ts.tag_q_count) as tag_q_count_sum
  from post_tags pt
  join tag_stats ts on ts.tag = pt.tag
  group by pt.PostId
),
user_post_stats as (
  select
    ps.OwnerUserId,
    avg(ps.composite_score) as u_avg,
    stddev_pop(ps.composite_score) as u_std
  from post_scores ps
  group by ps.OwnerUserId
),
scored_posts as (
  select
    ps.PostId,
    ps.OwnerUserId,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CreationDate,
    ps.Title,
    ps.engagement_rank,
    ps.recency_rank_for_user,
    ps.upvotes,
    ps.downvotes,
    ps.favorites,
    ps.bounty_total,
    ps.comment_count,
    ps.pos_comment_count,
    ps.first_upvote_at,
    ps.last_comment_at,
    ps.close_votes,
    ps.reopen_votes,
    ps.edit_events,
    ps.last_close_reason_id,
    ps.duplicate_of_count,
    ps.linked_count,
    ps.first_dup_link_at,
    ps.composite_score,
    pte.tags,
    pte.tag_avg_q_score,
    pte.tag_med_q_score,
    pte.tag_q_pos_sum,
    pte.tag_q_count_sum,
    up.u_avg,
    up.u_std,
    case
      when up.u_std is null or up.u_std = 0 then null
      else (ps.composite_score - up.u_avg) / nullif(up.u_std,0)
    end as user_zscore
  from post_scores ps
  left join post_tag_enrichment pte on pte.PostId = ps.PostId
  left join user_post_stats up on up.OwnerUserId = ps.OwnerUserId
),
user_enriched as (
  select
    up.UserId,
    up.Reputation,
    up.UserCreated,
    up.UserViews,
    up.UserUpVotes,
    up.UserDownVotes,
    up.Location,
    up.total_questions,
    up.total_answers,
    up.avg_nonzero_post_score,
    up.active_days,
    coalesce(bt.gold_badges,0) as gold_badges,
    coalesce(bt.silver_badges,0) as silver_badges,
    coalesce(bt.bronze_badges,0) as bronze_badges,
    coalesce(bt.tag_badges,0) as tag_badges
  from user_profile up
  left join badge_tiers bt on bt.UserId = up.UserId
),
candidate_posts as (
  (
    select PostId, OwnerUserId, composite_score, user_zscore, engagement_rank, recency_rank_for_user
    from scored_posts
    where recency_rank_for_user <= 3
  )
  union
  (
    select PostId, OwnerUserId, composite_score, user_zscore, engagement_rank, recency_rank_for_user
    from scored_posts
    where engagement_rank <= 100
  )
  union
  (
    select PostId, OwnerUserId, composite_score, user_zscore, engagement_rank, recency_rank_for_user
    from scored_posts
    where user_zscore is not null and user_zscore >= 1.5
  )
),
ranked_candidates as (
  select
    cp.PostId,
    cp.OwnerUserId,
    cp.composite_score,
    cp.user_zscore,
    row_number() over (partition by cp.OwnerUserId order by coalesce(cp.user_zscore, -1e9) desc, cp.composite_score desc) as rn
  from candidate_posts cp
),
final_posts as (
  select rc.PostId
  from ranked_candidates rc
  where rc.rn <= 5
)
select
  sp.PostId,
  sp.OwnerUserId,
  coalesce(u.DisplayName, 'Anonymous') as OwnerName,
  ue.Reputation,
  ue.Location,
  ue.gold_badges,
  ue.silver_badges,
  ue.bronze_badges,
  sp.Score as PostScore,
  sp.ViewCount,
  sp.AnswerCount,
  sp.upvotes,
  sp.downvotes,
  sp.favorites,
  sp.bounty_total,
  sp.comment_count,
  sp.close_votes,
  sp.duplicate_of_count,
  sp.composite_score,
  round(cast(sp.user_zscore as numeric), 3) as user_zscore,
  sp.Title,
  coalesce(array_to_string(sp.tags, ', '), '') as tags,
  sp.tag_avg_q_score,
  sp.tag_med_q_score,
  sp.first_upvote_at,
  sp.last_comment_at,
  sp.first_dup_link_at,
  case
    when sp.last_close_reason_id is not null then crt.Name
    else null
  end as last_close_reason,
  ct.is_controversial
from final_posts fp
join scored_posts sp on sp.PostId = fp.PostId
left join Users u on u.Id = sp.OwnerUserId
left join user_enriched ue on ue.UserId = sp.OwnerUserId
left join controversial ct on ct.PostId = sp.PostId
left join CloseReasonTypes crt on crt.Id = sp.last_close_reason_id
where not (
  sp.Title is null
  or trim(sp.Title) = ''
  or (sp.Score <= 0 and coalesce(sp.upvotes,0) = 0 and coalesce(sp.favorites,0) = 0)
)
order by sp.composite_score desc, sp.ViewCount desc, sp.Score desc
limit 250;