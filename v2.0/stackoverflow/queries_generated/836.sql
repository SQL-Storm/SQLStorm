-- {"query": "836.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3418} 
with
-- recent active users with badge diversity and vote behavior
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(distinct b.name) as distinct_badges,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
    count(*) filter (where v.votetypeid in (8,9) and v.bountyamount is not null) as bounty_actions
  from users u
  left join badges b on b.userid = u.id
  left join votes v on v.userid = u.id
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '5 years' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, location_norm
),
-- questions with rich metadata and normalized tags
questions as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.closeddate,
    p.title,
    p.tags,
    p.acceptedanswerid,
    array_length(string_to_array(coalesce(substring(p.tags, 2, greatest(length(p.tags)-2,0)), ''), '><'), 1) as tag_count,
    string_to_array(coalesce(nullif(substring(p.tags, 2, greatest(length(p.tags)-2,0)), ''), ''), '><') as tag_array
  from posts p
  where p.posttypeid = 1
),
-- fast tag expansion using unnest with ordinality
q_tags as (
  select
    q.id as question_id,
    lower(trim(tg)) as tagname,
    ord
  from questions q
  left join lateral unnest(q.tag_array) with ordinality as tg(tg, ord) on true
),
-- compute per-question engagement and closure details
question_stats as (
  select
    q.id,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.acceptedanswerid,
    q.tag_count,
    -- weighted engagement: log views + answers*5 + favorites*3 + score*2
    coalesce(ln(nullif(q.viewcount,0)), 0) + coalesce(q.answercount,0)*5 + coalesce(q.favoritecount,0)*3 + coalesce(q.score,0)*2 as engagement_index,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
    max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
  from questions q
  left join posthistory ph on ph.postid = q.id and ph.posthistorytypeid in (10,11)
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.favoritecount, q.acceptedanswerid, q.tag_count
),
-- map close reasons
close_reasons as (
  select crt.id, crt.name from closereasontypes crt
),
-- answers with owner and score
answers as (
  select
    a.id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.score as answer_score,
    a.creationdate as answer_date
  from posts a
  where a.posttypeid = 2
),
-- aggregate per question answers
answer_stats as (
  select
    a.question_id,
    count(*) as answers_total,
    sum(case when a.answer_score > 0 then 1 else 0 end) as answers_positive,
    max(a.answer_score) as best_answer_score,
    count(distinct a.answerer_id) as distinct_answerers,
    min(a.answer_date) as first_answer_at
  from answers a
  group by a.question_id
),
-- voting summary on questions
question_votes as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  join posts p on p.id = v.postid and p.posttypeid = 1
  group by v.postid
),
-- join tag table for popularity and properties
tag_meta as (
  select
    t.tagname,
    t.count as tag_usage_count,
    coalesce(t.ismoderatoronly::int, 0) as is_mod_only,
    coalesce(t.isrequired::int, 0) as is_required
  from tags t
),
-- per-question primary tag determined by highest global usage, tie-break by tag order
primary_tag as (
  select qt.question_id,
         (array_agg(qt.tagname order by tm.tag_usage_count desc nulls last, qt.ord asc))[1] as primary_tag
  from q_tags qt
  left join tag_meta tm on tm.tagname = qt.tagname
  group by qt.question_id
),
-- detect duplicates and linked questions
link_summary as (
  select
    pl.postid as question_id,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as normal_links
  from postlinks pl
  group by pl.postid
),
-- comment activity windowed per question
comment_activity as (
  select
    c.postid as question_id,
    count(*) as comments_total,
    max(c.creationdate) as last_comment_at,
    avg(c.score) as avg_comment_score
  from comments c
  join posts p on p.id = c.postid and p.posttypeid = 1
  group by c.postid
),
-- compile everything into a denormalized view with window functions
q_enriched as (
  select
    qs.id as question_id,
    qs.owneruserid,
    qs.creationdate,
    qs.score,
    qs.viewcount,
    qs.answercount,
    qs.favoritecount,
    qs.acceptedanswerid,
    qs.tag_count,
    qs.engagement_index,
    qs.first_closed_at,
    qs.last_reopened_at,
    cr.name as last_close_reason_name,
    coalesce(av.answers_total, 0) as answers_total,
    coalesce(av.answers_positive, 0) as answers_positive,
    coalesce(av.best_answer_score, 0) as best_answer_score,
    coalesce(av.distinct_answerers, 0) as distinct_answerers,
    av.first_answer_at,
    coalesce(qv.upvotes, 0) as upvotes,
    coalesce(qv.downvotes, 0) as downvotes,
    coalesce(qv.favorites_legacy, 0) as favorites_legacy,
    coalesce(qv.bounty_started, 0) as bounty_started,
    coalesce(qv.bounty_awarded, 0) as bounty_awarded,
    coalesce(ls.duplicate_links, 0) as duplicate_links,
    coalesce(ls.normal_links, 0) as normal_links,
    coalesce(ca.comments_total, 0) as comments_total,
    ca.last_comment_at,
    coalesce(ca.avg_comment_score, 0) as avg_comment_score,
    pt.primary_tag,
    -- windowed ranks and percentiles
    row_number() over (order by qs.engagement_index desc, qs.viewcount desc) as overall_rank,
    rank() over (partition by pt.primary_tag order by qs.engagement_index desc) as rank_within_primary_tag,
    ntile(10) over (order by qs.engagement_index desc) as engagement_decile,
    percentile_disc(0.5) within group (order by qs.viewcount) over () as global_viewcount_median,
    sum(qs.viewcount) over (order by qs.creationdate rows between unbounded preceding and current row) as cumulative_views_by_time
  from question_stats qs
  left join close_reasons cr on cr.id = qs.last_close_reason_id
  left join answer_stats av on av.question_id = qs.id
  left join question_votes qv on qv.question_id = qs.id
  left join link_summary ls on ls.question_id = qs.id
  left join comment_activity ca on ca.question_id = qs.id
  left join primary_tag pt on pt.question_id = qs.id
),
-- correlate with active users, classify behavior, and compute rolling activity windows
user_question as (
  select
    qe.*,
    au.displayname as owner_displayname,
    au.reputation as owner_reputation,
    au.location_norm,
    au.gold_badges,
    au.silver_badges,
    au.bronze_badges,
    au.distinct_badges,
    au.upvotes_cast,
    au.downvotes_cast,
    au.bounty_actions,
    case
      when qe.acceptedanswerid is not null then 1
      when qe.answers_total > 0 and qe.best_answer_score >= 1 then 1
      else 0
    end as has_good_answer,
    case
      when qe.first_closed_at is not null and qe.last_reopened_at is null then 'Closed'
      when qe.first_closed_at is not null and qe.last_reopened_at is not null then 'Closed/Reopened'
      else 'Open'
    end as closure_state,
    -- rolling count of questions by owner in 30-day window
    count(*) over (
      partition by qe.owneruserid
      order by qe.creationdate
      range between interval '30 days' preceding and current row
    ) as rolling_q_30d_by_user
  from q_enriched qe
  left join active_users au on au.user_id = qe.owneruserid
),
-- compute tag-level aggregates via set operators to stress planner
tag_levels as (
  select primary_tag as tagname, count(*) as q_count, avg(engagement_index) as avg_eng, sum(viewcount) as views
  from user_question
  where primary_tag is not null
  group by primary_tag
  union all
  select '<<UN-TAGGED>>', count(*), avg(engagement_index), sum(viewcount)
  from user_question
  where primary_tag is null
),
-- identify top N per tag using distinct on + window to vary access paths
top_per_tag as (
  select distinct on (uq.primary_tag)
    uq.primary_tag,
    uq.question_id,
    uq.engagement_index,
    uq.viewcount,
    uq.score
  from user_question uq
  where uq.primary_tag is not null
  order by uq.primary_tag, uq.engagement_index desc, uq.viewcount desc, uq.score desc
),
-- correlate duplicates with their canonical targets, prefer highest-scored target
duplicate_targets as (
  select
    pl.postid as dup_id,
    pl.relatedpostid as target_id,
    p.score as target_score,
    row_number() over (partition by pl.postid order by p.score desc nulls last, p.viewcount desc nulls last) as rn
  from postlinks pl
  join posts p on p.id = pl.relatedpostid
  where pl.linktypeid = 3
),
canonical_map as (
  select dup_id, target_id
  from duplicate_targets
  where rn = 1
),
-- resolved canonical engagement by correlated subquery
canonical_engagement as (
  select
    uq.question_id,
    coalesce((
      select qe2.engagement_index
      from q_enriched qe2
      join canonical_map cm on cm.target_id = qe2.question_id
      where cm.dup_id = uq.question_id
      limit 1
    ), uq.engagement_index) as effective_engagement
  from user_question uq
)
select
  uq.question_id,
  coalesce(uq.owneruserid, -1) as owneruserid,
  coalesce(uq.owner_displayname, '[deleted]') as owner_displayname,
  uq.creationdate,
  uq.primary_tag,
  coalesce(tl.q_count, 0) as tag_q_count,
  coalesce(tl.avg_eng, 0) as tag_avg_engagement,
  coalesce(tl.views, 0) as tag_total_views,
  uq.viewcount,
  uq.score,
  uq.upvotes,
  uq.downvotes,
  uq.answercount,
  uq.answers_total,
  uq.answers_positive,
  uq.best_answer_score,
  uq.comments_total,
  uq.engagement_index,
  ce.effective_engagement,
  uq.overall_rank,
  uq.rank_within_primary_tag,
  uq.engagement_decile,
  uq.closure_state,
  uq.last_close_reason_name,
  uq.duplicate_links,
  uq.normal_links,
  uq.bounty_started,
  uq.bounty_awarded,
  uq.global_viewcount_median,
  uq.cumulative_views_by_time,
  uq.has_good_answer,
  uq.rolling_q_30d_by_user,
  au_case.top_tag_leader as is_top_for_tag,
  -- complex predicate classification
  case
    when uq.engagement_index >= coalesce(tl.avg_eng, 0) * 3 and uq.viewcount > 1000 and uq.upvotes >= uq.downvotes * 5 then 'Breakout'
    when uq.engagement_index >= coalesce(tl.avg_eng, 0) * 1.5 and uq.viewcount > 500 then 'High'
    when uq.engagement_index <= coalesce(tl.avg_eng, 0) * 0.5 and uq.downvotes > uq.upvotes then 'Underperform'
    else 'Typical'
  end as perf_bucket
from user_question uq
left join tag_levels tl on tl.tagname = coalesce(uq.primary_tag, '<<UN-TAGGED>>')
left join canonical_engagement ce on ce.question_id = uq.question_id
left join lateral (
  select case when exists (
    select 1 from top_per_tag tpt
    where tpt.primary_tag = uq.primary_tag and tpt.question_id = uq.question_id
  ) then 1 else 0 end as top_tag_leader
) au_case on true
where
  -- complicated where with null logic and string operations
  (
    uq.primary_tag is null
    or uq.primary_tag !~* '(^|-)meta($|-)'
  )
  and coalesce(uq.viewcount, 0) + coalesce(uq.answercount, 0) + coalesce(uq.favoritecount, 0) > 0
  and (
    uq.first_closed_at is null
    or uq.last_reopened_at is not null
    or (uq.last_close_reason_name is not null and uq.last_close_reason_name not ilike '%off-topic%')
  )
order by
  perf_bucket,
  uq.engagement_decile,
  uq.overall_rank
limit 500;