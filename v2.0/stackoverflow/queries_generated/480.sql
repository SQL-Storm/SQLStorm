-- {"query": "480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3061} 
with
-- Parameterizable time window and thresholds
params as (
  select
    date_trunc('month', now()) - interval '12 months' as start_ts,
    date_trunc('month', now()) as end_ts,
    10 as min_answers,
    5 as min_comments,
    3 as min_tags
),
-- Questions in window with exploded tags
q as (
  select
    p.Id as question_id,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_arr
  from Posts p
  join params pa on p.PostTypeId = 1
  where p.CreationDate >= pa.start_ts and p.CreationDate < pa.end_ts
),
q_tags as (
  select
    question_id,
    lower(trim(t)) as tag
  from q
  cross join lateral unnest(tag_arr) as t
),
-- Answer rollup with acceptance and user stats
answers as (
  select
    a.ParentId as question_id,
    count(*) as answer_count,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as accepted_count,
    avg(a.Score) as avg_answer_score,
    max(a.Score) as max_answer_score
  from Posts a
  join Posts q on q.Id = a.ParentId and a.PostTypeId = 2
  join params pa on q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
  group by a.ParentId
),
-- Comment rollup on questions and their answers
comments_rollup as (
  select
    q.Id as question_id,
    count(cq.Id) + coalesce(sum(ac.cnt),0) as total_comments
  from Posts q
  left join Comments cq on cq.PostId = q.Id
  left join lateral (
    select a.ParentId, count(ca.Id) as cnt
    from Posts a
    left join Comments ca on ca.PostId = a.Id
    where a.ParentId = q.Id and a.PostTypeId = 2
    group by a.ParentId
  ) ac on ac.ParentId = q.Id
  join params pa on q.PostTypeId = 1 and q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
  group by q.Id
),
-- Distinct tag diversity per question
tag_diversity as (
  select question_id, count(distinct tag) as distinct_tags
  from q_tags
  group by question_id
),
-- Votes summary for questions
q_votes as (
  select
    v.PostId as question_id,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites
  from Votes v
  join Posts q on q.Id = v.PostId and q.PostTypeId = 1
  join params pa on q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
  group by v.PostId
),
-- Post history events for closures and protections
q_history as (
  select
    ph.PostId as question_id,
    sum(case when ph.PostHistoryTypeId in (10,35) then 1 else 0 end) as close_events,
    sum(case when ph.PostHistoryTypeId = 19 then 1 else 0 end) as protect_events,
    max(case when ph.PostHistoryTypeId in (10,35) then ph.CreationDate end) as last_close_date
  from PostHistory ph
  join Posts q on q.Id = ph.PostId and q.PostTypeId = 1
  join params pa on q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
  group by ph.PostId
),
-- Related/duplicate link counts
q_links as (
  select
    pl.PostId as question_id,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as linked_out,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as duplicates_of
  from PostLinks pl
  join Posts q on q.Id = pl.PostId and q.PostTypeId = 1
  join params pa on q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
  group by pl.PostId
),
-- User reputation snapshot windowed by question creation (correlated)
asker_rep as (
  select
    q.Id as question_id,
    u.Id as user_id,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    rank() over (partition by q.Id order by u.Reputation desc, u.UpVotes - u.DownVotes desc nulls last) as rep_rank
  from Posts q
  left join Users u on u.Id = q.OwnerUserId
  join params pa on q.PostTypeId = 1 and q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
),
-- Rolling activity window per tag (window functions)
tag_activity as (
  select
    qt.tag,
    date_trunc('month', q.CreationDate) as ymon,
    count(*) as q_cnt,
    sum(q.Score) as q_score_sum
  from q
  join q_tags qt on qt.question_id = q.Id
  group by qt.tag, date_trunc('month', q.CreationDate)
),
tag_activity_win as (
  select
    tag,
    ymon,
    q_cnt,
    q_score_sum,
    sum(q_cnt) over (partition by tag order by ymon rows between 2 preceding and current row) as q_cnt_3m,
    avg(q_score_sum::numeric) over (partition by tag order by ymon rows between 5 preceding and current row) as avg_score_6m
  from tag_activity
),
-- Compute z-score like outlier metric per question by comparing to tag rolling windows
question_tag_signal as (
  select
    qt.question_id,
    avg(
      case
        when taw.q_cnt_3m is null or taw.q_cnt_3m = 0 then 0
        else greatest(0, (q.Score - coalesce(taw.avg_score_6m, 0)) / nullif(sqrt(abs(taw.avg_score_6m)),0))
      end
    ) as tag_signal
  from q
  join q_tags qt on qt.question_id = q.Id
  left join tag_activity_win taw on taw.tag = qt.tag and taw.ymon = date_trunc('month', q.CreationDate)
  group by qt.question_id
),
-- Build a complex eligibility predicate with NULL logic
eligible as (
  select
    q.Id as question_id,
    case
      when a.answer_count >= pa.min_answers
           and cr.total_comments >= pa.min_comments
           and td.distinct_tags >= pa.min_tags
           and coalesce(qv.upvotes,0) - coalesce(qv.downvotes,0) > 0
      then true
      when qv.favorites is not null and qv.favorites >= 3 then true
      when q.Score >= 5 and coalesce(a.avg_answer_score,0) >= 1 then true
      else false
    end as is_hot_candidate
  from q
  join params pa on true
  left join answers a on a.question_id = q.Id
  left join comments_rollup cr on cr.question_id = q.Id
  left join tag_diversity td on td.question_id = q.Id
  left join q_votes qv on qv.question_id = q.Id
),
-- Dense rank questions by composite engagement
ranked as (
  select
    q.Id as question_id,
    q.CreationDate,
    q.Title,
    coalesce(a.answer_count,0) as answer_count,
    coalesce(a.accepted_count,0) as accepted_count,
    coalesce(cr.total_comments,0) as total_comments,
    coalesce(td.distinct_tags,0) as distinct_tags,
    coalesce(qv.upvotes,0) as upvotes,
    coalesce(qv.downvotes,0) as downvotes,
    coalesce(qv.favorites,0) as favorites,
    coalesce(ql.linked_out,0) as linked_out,
    coalesce(ql.duplicates_of,0) as duplicates_of,
    coalesce(qh.close_events,0) as close_events,
    qh.last_close_date,
    coalesce(qts.tag_signal,0) as tag_signal,
    coalesce(a.avg_answer_score,0) as avg_answer_score,
    coalesce(a.max_answer_score,0) as max_answer_score,
    e.is_hot_candidate,
    ar.Reputation as asker_reputation,
    ar.UpVotes as asker_upvotes,
    ar.DownVotes as asker_downvotes,
    dense_rank() over (
      order by
        (coalesce(qv.upvotes,0) - coalesce(qv.downvotes,0))*2
        + coalesce(a.answer_count,0)*1.5
        + coalesce(cr.total_comments,0)*0.5
        + coalesce(qv.favorites,0)*1.2
        + coalesce(qts.tag_signal,0)*2
        + case when e.is_hot_candidate then 5 else 0 end
        + least(coalesce(td.distinct_tags,0),10)*0.3
        - coalesce(qh.close_events,0)*3
        - coalesce(ql.duplicates_of,0)*2
        desc,
        q.CreationDate asc
    ) as engagement_rank
  from q
  left join answers a on a.question_id = q.Id
  left join comments_rollup cr on cr.question_id = q.Id
  left join tag_diversity td on td.question_id = q.Id
  left join q_votes qv on qv.question_id = q.Id
  left join q_links ql on ql.question_id = q.Id
  left join q_history qh on qh.question_id = q.Id
  left join question_tag_signal qts on qts.question_id = q.Id
  left join eligible e on e.question_id = q.Id
  left join lateral (
    select user_id, Reputation, UpVotes, DownVotes
    from asker_rep ar
    where ar.question_id = q.Id and ar.rep_rank = 1
  ) ar on true
),
-- Build human-friendly tag string, sample of top tags per question
tag_samples as (
  select
    qt.question_id,
    string_agg(qt.tag, ', ' order by qt.tag) as tag_list,
    string_agg(qt.tag, ', ' order by qt.tag) filter (where rn <= 3) as top3_tags
  from (
    select
      qt.question_id,
      qt.tag,
      row_number() over (partition by qt.question_id order by count(*) over (partition by qt.question_id, qt.tag) desc, qt.tag) as rn
    from q_tags qt
  ) qt
  group by qt.question_id
),
-- Identify questions missing owners or with community ownership
ownership_flags as (
  select
    q.Id as question_id,
    case when q.OwnerUserId is null then 'orphan'
         when q.OwnerUserId = -1 then 'community'
         else 'owned'
    end as owner_type
  from Posts q
  join params pa on q.PostTypeId = 1 and q.CreationDate >= pa.start_ts and q.CreationDate < pa.end_ts
),
-- Build enriched titles with string expressions
title_enriched as (
  select
    q.Id as question_id,
    coalesce(nullif(trim(q.Title), ''), '[untitled]') as title_clean,
    '[' || coalesce(ts.top3_tags, 'no-tags') || '] ' ||
    regexp_replace(coalesce(nullif(trim(q.Title), ''), '[untitled]'), '\s+', ' ', 'g') as decorated_title
  from q
  left join tag_samples ts on ts.question_id = q.Id
)
select
  r.engagement_rank,
  r.question_id,
  te.decorated_title as title,
  ts.tag_list,
  r.answer_count,
  r.accepted_count,
  r.total_comments,
  r.distinct_tags,
  r.upvotes,
  r.downvotes,
  r.favorites,
  r.linked_out,
  r.duplicates_of,
  r.close_events,
  r.last_close_date,
  r.tag_signal,
  r.avg_answer_score,
  r.max_answer_score,
  r.is_hot_candidate,
  of.owner_type,
  r.asker_reputation,
  r.asker_upvotes,
  r.asker_downvotes,
  -- Complex predicate projection
  case
    when r.close_events > 0 and r.duplicates_of > 0 then 'closed-dup'
    when r.close_events > 0 then 'closed'
    when r.duplicates_of > 0 then 'dup'
    else 'open'
  end as status_bucket
from ranked r
left join tag_samples ts on ts.question_id = r.question_id
left join ownership_flags of on of.question_id = r.question_id
left join title_enriched te on te.question_id = r.question_id
where
  -- Complicated where with NULL-safe logic and mixed conditions
  (
    r.is_hot_candidate
    or (
      coalesce(r.upvotes,0) >= 3
      and (coalesce(r.answer_count,0) >= 2 or coalesce(r.total_comments,0) >= 5)
      and not (coalesce(r.close_events,0) > 0 and coalesce(r.duplicates_of,0) > 0)
    )
  )
  and (
    r.asker_reputation is null
    or r.asker_reputation >= 100
    or (r.asker_upvotes - r.asker_downvotes) >= 10
  )
order by r.engagement_rank
limit 200;