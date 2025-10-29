-- {"query": "15.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3104} 
with params as (
  select
    interval '365 days' as recent_window,
    50 as min_rep,
    3 as min_answers,
    5 as min_comments
),
recent_questions as (
  select
    q.Id,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.AcceptedAnswerId,
    coalesce(q.AnswerCount, 0) as AnswerCount,
    coalesce(q.CommentCount, 0) as CommentCount,
    q.Title,
    q.Tags
  from Posts q
  join PostTypes pt on pt.Id = q.PostTypeId and pt.Name = 'Question'
  cross join params p
  where q.CreationDate >= now() - p.recent_window
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreated,
    coalesce(u.Location, 'unknown') as Location,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    row_number() over (order by u.Reputation desc, u.Id) as rep_rank
  from Users u
),
answers as (
  select
    a.Id,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreated,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as answer_rank,
    count(*) over (partition by a.ParentId) as answers_on_q
  from Posts a
  join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
),
comments_agg as (
  select
    c.PostId,
    count(*) as comment_count,
    sum(case when c.Score > 0 then 1 else 0 end) as pos_comments,
    max(c.Score) as max_comment_score,
    min(c.CreationDate) as first_comment_at,
    max(c.CreationDate) as last_comment_at
  from Comments c
  group by c.PostId
),
votes_agg as (
  select
    v.PostId,
    count(*) filter (where vt.Name = 'UpMod') as upvotes,
    count(*) filter (where vt.Name = 'DownMod') as downvotes,
    count(*) filter (where vt.Name = 'Favorite') as favorites,
    count(*) filter (where vt.Name = 'BountyStart') as bounties_started,
    sum(v.BountyAmount) filter (where vt.Name in ('BountyStart','BountyClose')) as bounty_amount_sum,
    max(v.CreationDate) filter (where vt.Name = 'UpMod') as last_upvote_at
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
tag_expanded as (
  select
    q.Id as QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) as tag
  from recent_questions q
  where q.Tags is not null
),
tag_quality as (
  select
    te.tag,
    count(*) as q_count,
    avg(q.Score::numeric) as avg_q_score,
    percentile_cont(0.9) within group (order by q.ViewCount) as p90_views
  from tag_expanded te
  join recent_questions q on q.Id = te.QuestionId
  group by te.tag
  having count(*) >= 5
),
closed_events as (
  select
    ph.PostId,
    min(ph.CreationDate) as first_closed_at,
    count(*) filter (where ph.PostHistoryTypeId = 10) as close_events,
    count(*) filter (where ph.PostHistoryTypeId = 11) as reopen_events,
    max((case when ph.PostHistoryTypeId = 10 then ph.Comment end)) as last_close_reason_raw
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId as DuplicateOf,
    pl.RelatedPostId as Original,
    min(pl.CreationDate) as first_dup_link_at,
    count(*) as dup_link_count
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
  group by pl.PostId, pl.RelatedPostId
),
owner_badges as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as gold_count,
    count(*) filter (where b.Class = 2) as silver_count,
    count(*) filter (where b.Class = 3) as bronze_count,
    max(b.Date) as last_badge_at
  from Badges b
  group by b.UserId
),
question_enriched as (
  select
    q.*,
    ua.Reputation as owner_rep,
    ua.rep_rank as owner_rep_rank,
    ua.Location as owner_location,
    coalesce(ob.gold_count,0) as owner_gold,
    coalesce(ob.silver_count,0) as owner_silver,
    coalesce(ob.bronze_count,0) as owner_bronze,
    va.upvotes,
    va.downvotes,
    va.favorites,
    coalesce(va.bounties_started,0) as bounties_started,
    coalesce(va.bounty_amount_sum,0) as bounty_amount_sum,
    ca.comment_count,
    ca.pos_comments,
    ca.max_comment_score,
    ce.first_closed_at,
    ce.close_events,
    ce.reopen_events,
    ce.last_close_reason_raw,
    dl.first_dup_link_at,
    dl.dup_link_count,
    case
      when q.AcceptedAnswerId is not null then 1
      when exists (
        select 1 from answers a2
        where a2.QuestionId = q.Id and a2.AnswerScore >= 0
      ) then 0
      else null
    end as has_viable_answers_flag
  from recent_questions q
  left join user_stats ua on ua.UserId = q.OwnerUserId
  left join owner_badges ob on ob.UserId = q.OwnerUserId
  left join votes_agg va on va.PostId = q.Id
  left join comments_agg ca on ca.PostId = q.Id
  left join closed_events ce on ce.PostId = q.Id
  left join dup_links dl on dl.DuplicateOf = q.Id
),
best_answers as (
  select
    a.QuestionId,
    a.Id as BestAnswerId,
    a.AnswerOwnerId,
    a.AnswerScore,
    a.AnswerCreated,
    a.answers_on_q
  from answers a
  where a.answer_rank = 1
),
answerer_stats as (
  select
    a.AnswerOwnerId as UserId,
    count(*) as total_answers,
    avg(a.AnswerScore::numeric) as avg_answer_score,
    max(a.AnswerScore) as max_answer_score,
    min(a.AnswerCreated) as first_answer_at,
    max(a.AnswerCreated) as last_answer_at
  from answers a
  group by a.AnswerOwnerId
),
title_signals as (
  select
    qe.Id as QuestionId,
    length(coalesce(qe.Title, '')) as title_len,
    (position('how' in lower(coalesce(qe.Title,''))) > 0)::int +
    (position('why' in lower(coalesce(qe.Title,''))) > 0)::int +
    (position('error' in lower(coalesce(qe.Title,''))) > 0)::int +
    (position('exception' in lower(coalesce(qe.Title,''))) > 0)::int +
    (position('performance' in lower(coalesce(qe.Title,''))) > 0)::int as title_keyword_hits
  from question_enriched qe
),
tag_top as (
  select
    te.QuestionId,
    string_agg(tq.tag || ':' || round(tq.avg_q_score::numeric,2)::text, ',' order by tq.avg_q_score desc) as tag_quality_summary,
    max(tq.p90_views) as max_tag_p90_views
  from tag_expanded te
  join tag_quality tq on tq.tag = te.tag
  group by te.QuestionId
),
question_quality_score as (
  select
    qe.Id as QuestionId,
    qe.Score,
    qe.ViewCount,
    coalesce(qe.upvotes,0) - coalesce(qe.downvotes,0) as net_votes,
    coalesce(qe.favorites,0) as favorites,
    coalesce(qe.comment_count,0) as comment_count,
    coalesce(qe.pos_comments,0) as pos_comments,
    coalesce(qe.owner_rep,0) as owner_rep,
    coalesce(ts.title_len,0) as title_len,
    coalesce(ts.title_keyword_hits,0) as title_keyword_hits,
    coalesce(qe.owner_gold,0) as owner_gold,
    coalesce(qe.owner_silver,0) as owner_silver,
    coalesce(qe.owner_bronze,0) as owner_bronze,
    case when qe.first_closed_at is not null then 1 else 0 end as is_closed,
    case when qe.first_closed_at is null and qe.AcceptedAnswerId is not null then 1 else 0 end as solved_open,
    round((
      coalesce(qe.Score,0)*2
      + coalesce(qe.ViewCount,0)/100.0
      + (coalesce(qe.upvotes,0) - coalesce(qe.downvotes,0))*1.5
      + coalesce(qe.favorites,0)*2
      + least(coalesce(qe.comment_count,0), 20)*0.5
      + coalesce(ts.title_keyword_hits,0)*1.0
      + ln(greatest(coalesce(qe.owner_rep,1),1))::numeric
      + coalesce(qe.owner_gold,0)*3
      + coalesce(qe.owner_silver,0)*1.5
      + coalesce(qe.owner_bronze,0)*0.5
      - coalesce(qe.close_events,0)*4
      - coalesce(qe.dup_link_count,0)*5
    )::numeric, 2) as quality_score
  from question_enriched qe
  left join title_signals ts on ts.QuestionId = qe.Id
),
ranked as (
  select
    qqs.QuestionId,
    qqs.quality_score,
    qqs.Score,
    qqs.ViewCount,
    qqs.net_votes,
    qqs.favorites,
    qqs.comment_count,
    qqs.pos_comments,
    qqs.owner_rep,
    qqs.title_len,
    qqs.title_keyword_hits,
    qqs.is_closed,
    qqs.solved_open,
    row_number() over (order by qqs.quality_score desc, qqs.Score desc, qqs.ViewCount desc) as q_rank,
    ntile(10) over (order by qqs.quality_score desc) as decile
  from question_quality_score qqs
),
filtering as (
  select
    r.*,
    qe.OwnerUserId,
    qe.Title,
    qe.Tags,
    qe.AcceptedAnswerId,
    qe.first_closed_at,
    qe.last_close_reason_raw,
    bt.BestAnswerId,
    ba.AnswerOwnerId,
    aa.avg_answer_score,
    aa.total_answers,
    tt.tag_quality_summary,
    tt.max_tag_p90_views
  from ranked r
  join question_enriched qe on qe.Id = r.QuestionId
  left join best_answers bt on bt.QuestionId = r.QuestionId
  left join answerer_stats aa on aa.UserId = bt.AnswerOwnerId
  left join tag_top tt on tt.QuestionId = r.QuestionId
  cross join params p
  where
    (qe.AnswerCount is null or qe.AnswerCount >= p.min_answers)
    and coalesce(qe.comment_count,0) >= p.min_comments
    and coalesce(qe.owner_rep,0) >= p.min_rep
    and (
      qe.first_closed_at is null
      or extract(epoch from (now() - qe.first_closed_at)) > 86400
    )
),
dup_check as (
  select
    f.*,
    case when exists (
      select 1
      from PostLinks pl
      join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
      where pl.PostId = f.QuestionId
    ) then 1 else 0 end as is_marked_duplicate
  from filtering f
)
select
  d.QuestionId,
  d.q_rank,
  d.decile,
  d.quality_score,
  d.Score as question_score,
  d.ViewCount as question_views,
  d.net_votes,
  d.favorites,
  d.comment_count,
  d.pos_comments,
  d.owner_rep,
  d.title_len,
  d.title_keyword_hits,
  d.is_closed,
  d.solved_open,
  d.is_marked_duplicate,
  coalesce(d.last_close_reason_raw, 'n/a') as last_close_reason_raw,
  coalesce(d.max_tag_p90_views, 0) as max_tag_p90_views,
  coalesce(d.tag_quality_summary, '') as tag_quality_summary,
  coalesce(d.BestAnswerId, 0) as BestAnswerId,
  coalesce(d.avg_answer_score, 0)::numeric(10,2) as best_answerer_avg_score,
  coalesce(d.total_answers, 0) as best_answerer_total_answers,
  d.OwnerUserId as question_owner_id,
  coalesce(d.AcceptedAnswerId, 0) as AcceptedAnswerId,
  substring(coalesce(d.Title,''), 1, 140) as TitleSnippet,
  coalesce(d.Tags, '') as Tags,
  case
    when d.quality_score >= percentile_cont(0.75) within group (order by d.quality_score) over ()
      then 'top_quartile'
    when d.quality_score <= percentile_cont(0.25) within group (order by d.quality_score) over ()
      then 'bottom_quartile'
    else 'middle_half'
  end as quality_bucket
from dup_check d
where d.decile in (1,2,3,4,5,6,7,8,9,10)
order by d.q_rank
limit 250;