-- {"query": "896.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3719} 
with
-- Active users with recent activity and basic stats
active_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.upvotes,
    u.downvotes,
    u.views,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm
  from users u
  where u.reputation > 0
    and u.creationdate <= now()
    and (u.lastaccessdate is null or u.lastaccessdate <= now())
),
-- Expand questions with parsed tags and classify lifecycle
questions as (
  select
    p.id as question_id,
    p.owneruserid,
    p.creationdate as q_created,
    p.score as q_score,
    p.viewcount as q_views,
    p.answercount,
    p.acceptedanswerid,
    p.closeddate,
    p.title,
    p.tags,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_arr,
    case
      when p.closeddate is not null then 'closed'
      when p.acceptedanswerid is not null then 'accepted'
      when coalesce(p.answercount,0) > 0 then 'answered'
      else 'open'
    end as q_state
  from posts p
  where p.posttypeid = 1
    and p.creationdate is not null
),
-- Answers joined to questions
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_owner_id,
    a.creationdate as a_created,
    a.score as a_score
  from posts a
  where a.posttypeid = 2
),
-- First answer per question (by creation time), with tie-breaking on lowest answer id
first_answer as (
  select distinct on (question_id)
    question_id,
    answer_id,
    a_created,
    a_score
  from (
    select
      ans.question_id,
      ans.answer_id,
      ans.a_created,
      ans.a_score,
      row_number() over (partition by ans.question_id order by ans.a_created asc, ans.answer_id asc) as rn
    from answers ans
  ) s
  where rn = 1
  order by question_id, a_created, answer_id
),
-- Time to first answer and to accepted answer
answer_timings as (
  select
    q.question_id,
    extract(epoch from (fa.a_created - q.q_created)) as secs_to_first_answer,
    extract(epoch from (
      case when q.acceptedanswerid is not null
           then (select a.creationdate from posts a where a.id = q.acceptedanswerid)
      end - q.q_created
    )) as secs_to_accept
  from questions q
  left join first_answer fa on fa.question_id = q.question_id
),
-- Vote aggregates per question (up, down, favorite/bookmark legacy)
vote_agg as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    count(*) as total_votes,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
-- Comment counts and earliest comment time per question
comment_agg as (
  select
    c.postid as question_id,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
    min(c.creationdate) as first_comment_at
  from comments c
  group by c.postid
),
-- Historical close reasons per question (latest effective close entry if any)
close_reasons as (
  select
    ph.postid as question_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopened_at,
    (
      select crt.name
      from posthistory ph2
      left join closereasontypes crt on crt.id::text = ph2.comment
      where ph2.postid = ph.postid
        and ph2.posthistorytypeid = 10
      order by ph2.creationdate desc
      limit 1
    ) as last_close_reason
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
-- Tag popularity snapshot for weighting
tag_weights as (
  select
    t.tagname,
    t.count as tag_count,
    ntile(10) over (order by t.count desc nulls last) as popularity_decile
  from tags t
),
-- Expand question tags and join weights
question_tag_weights as (
  select
    q.question_id,
    lower(trim(both from tag)) as tagname,
    tw.tag_count,
    coalesce(tw.popularity_decile, 10) as popularity_decile
  from questions q
  left join lateral unnest(q.tag_arr) as tag on true
  left join tag_weights tw on lower(tw.tagname) = lower(trim(both from tag))
),
-- Aggregate tag signals per question
question_tag_agg as (
  select
    question_id,
    count(*) as tag_count,
    coalesce(sum(tag_count),0) as sum_tag_global_count,
    avg(popularity_decile::numeric) as avg_popularity_decile
  from question_tag_weights
  group by question_id
),
-- Badge signals for owners around question creation window
owner_badge_window as (
  select
    q.question_id,
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
  from questions q
  join badges b
    on b.userid = q.owneruserid
   and b.date between q.q_created - interval '365 days' and q.q_created
  group by q.question_id, b.userid
),
-- Duplicate/related link signals
post_link_signals as (
  select
    pl.postid as question_id,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links,
    min(pl.creationdate) as first_link_at
  from postlinks pl
  group by pl.postid
),
-- Build a wide fact set
fact as (
  select
    q.question_id,
    q.owneruserid,
    q.q_created,
    q.q_score,
    q.q_views,
    q.answercount,
    q.acceptedanswerid,
    q.closeddate,
    q.title,
    qa.tag_count,
    qa.sum_tag_global_count,
    qa.avg_popularity_decile,
    vt.upvotes,
    vt.downvotes,
    vt.favorites,
    vt.total_votes,
    vt.first_vote_at,
    vt.last_vote_at,
    ca.comment_count,
    ca.pos_comment_count,
    ca.first_comment_at,
    cr.closed_at,
    cr.reopened_at,
    cr.last_close_reason,
    ow.gold_badges,
    ow.silver_badges,
    ow.bronze_badges,
    pls.duplicate_links,
    pls.related_links,
    pls.first_link_at,
    at.secs_to_first_answer,
    at.secs_to_accept
  from questions q
  left join question_tag_agg qa on qa.question_id = q.question_id
  left join vote_agg vt on vt.question_id = q.question_id
  left join comment_agg ca on ca.question_id = q.question_id
  left join close_reasons cr on cr.question_id = q.question_id
  left join owner_badge_window ow on ow.question_id = q.question_id
  left join post_link_signals pls on pls.question_id = q.question_id
  left join answer_timings at on at.question_id = q.question_id
),
-- Derive performance-heavy expressions and windowed ranks
scored as (
  select
    f.*,
    -- Engagement score combining votes, comments, and views with log scaling
    (
      coalesce(f.upvotes,0) * 5
      - coalesce(f.downvotes,0) * 4
      + coalesce(f.favorites,0) * 2
      + greatest(ln(1 + coalesce(f.q_views,0)::numeric), 0)
      + coalesce(f.comment_count,0) * 0.5
    ) as engagement_score,
    -- Speed metrics with null handling
    case
      when f.secs_to_first_answer is null then null
      when f.secs_to_first_answer < 0 then null
      else f.secs_to_first_answer
    end as secs_to_first_answer_norm,
    case
      when f.secs_to_accept is null or f.secs_to_accept < 0 then null
      else f.secs_to_accept
    end as secs_to_accept_norm,
    -- Content length proxies
    length(coalesce(f.title,'')) as title_len,
    -- Title lexical features
    regexp_count(coalesce(f.title,''), '\?') as qmark_count,
    (regexp_replace(lower(coalesce(f.title,'')), '\s+', ' ', 'g')) as title_norm,
    -- State flags
    (f.acceptedanswerid is not null)::int as has_accepted,
    (coalesce(f.answercount,0) > 0)::int as has_answers,
    (f.closeddate is not null)::int as is_closed,
    -- Complexity: composite quality index
    (
      coalesce(f.q_score,0)
      + coalesce(f.upvotes,0) - coalesce(f.downvotes,0)
      + (case when coalesce(f.answercount,0) > 0 then 2 else 0 end)
      + (case when f.acceptedanswerid is not null then 3 else 0 end)
      + (case when f.closeddate is not null then -4 else 0 end)
      + least(coalesce(f.tag_count,0), 5)
      + (10 - coalesce(round(f.avg_popularity_decile),10))
    )::numeric as quality_index
  from fact f
),
-- Rank questions per temporal buckets and tags
ranked as (
  select
    s.*,
    date_trunc('month', s.q_created) as month_bucket,
    dense_rank() over (partition by date_trunc('month', s.q_created) order by s.engagement_score desc nulls last, s.q_created asc, s.question_id asc) as rank_in_month,
    percent_rank() over (partition by date_trunc('month', s.q_created) order by s.quality_index desc nulls last) as pct_quality_month,
    row_number() over (order by coalesce(s.secs_to_first_answer_norm, 1e15) asc, s.q_created asc) as fastest_answer_rownum_global
  from scored s
),
-- Compute owner-centric aggregates
owner_agg as (
  select
    q.owneruserid as user_id,
    count(*) as asked_count,
    sum((q.acceptedanswerid is not null)::int) as accepted_count,
    avg(coalesce(fa.secs_to_first_answer, 0)) filter (where fa.secs_to_first_answer is not null) as avg_secs_to_first_answer,
    avg(q.score) as avg_q_score
  from questions q
  left join answer_timings fa on fa.question_id = q.question_id
  group by q.owneruserid
),
-- Combine owners with active users and reputation deciles
owner_enriched as (
  select
    au.id as user_id,
    au.displayname,
    au.reputation,
    au.location_norm,
    oa.asked_count,
    oa.accepted_count,
    coalesce(oa.avg_secs_to_first_answer, 0) as avg_secs_to_first_answer,
    oa.avg_q_score,
    ntile(10) over (order by au.reputation desc nulls last) as rep_decile
  from active_users au
  left join owner_agg oa on oa.user_id = au.id
),
-- Correlated subquery to get a user's latest post activity timestamp (question or answer)
owner_last_activity as (
  select
    u.user_id,
    (
      select max(p.lastactivitydate)
      from posts p
      where (p.owneruserid = u.user_id)
    ) as last_post_activity
  from owner_enriched u
),
-- Bring it all together and apply set operator to include some closed but high-engagement outliers
final_set as (
  select
    r.question_id,
    r.q_created,
    r.title,
    r.engagement_score,
    r.quality_index,
    r.rank_in_month,
    r.pct_quality_month,
    r.secs_to_first_answer_norm,
    r.secs_to_accept_norm,
    r.q_views,
    r.upvotes,
    r.downvotes,
    r.comment_count,
    r.tag_count,
    r.sum_tag_global_count,
    r.avg_popularity_decile,
    r.is_closed,
    r.has_answers,
    r.has_accepted,
    r.last_close_reason,
    oe.user_id as owner_id,
    oe.displayname as owner_name,
    oe.reputation as owner_reputation,
    oe.rep_decile as owner_rep_decile,
    oe.location_norm as owner_location,
    oe.asked_count as owner_asked_count,
    oe.accepted_count as owner_accepted_count,
    oe.avg_secs_to_first_answer as owner_avg_secs_to_first_answer,
    ola.last_post_activity,
    case
      when r.engagement_score >= percentile_disc(0.9) within group (order by r.engagement_score) over ()
       then 'P90+'
      when r.engagement_score >= percentile_disc(0.75) within group (order by r.engagement_score) over ()
       then 'P75-90'
      when r.engagement_score >= percentile_disc(0.5) within group (order by r.engagement_score) over ()
       then 'P50-75'
      else 'Sub-50'
    end as engagement_band
  from ranked r
  left join owner_enriched oe on oe.user_id = r.owneruserid
  left join owner_last_activity ola on ola.user_id = oe.user_id

  union all

  select
    r.question_id,
    r.q_created,
    r.title,
    r.engagement_score,
    r.quality_index,
    r.rank_in_month,
    r.pct_quality_month,
    r.secs_to_first_answer_norm,
    r.secs_to_accept_norm,
    r.q_views,
    r.upvotes,
    r.downvotes,
    r.comment_count,
    r.tag_count,
    r.sum_tag_global_count,
    r.avg_popularity_decile,
    r.is_closed,
    r.has_answers,
    r.has_accepted,
    r.last_close_reason,
    oe.user_id as owner_id,
    oe.displayname as owner_name,
    oe.reputation as owner_reputation,
    oe.rep_decile as owner_rep_decile,
    oe.location_norm as owner_location,
    oe.asked_count as owner_asked_count,
    oe.accepted_count as owner_accepted_count,
    oe.avg_secs_to_first_answer as owner_avg_secs_to_first_answer,
    ola.last_post_activity,
    'ClosedOutlier' as engagement_band
  from ranked r
  left join owner_enriched oe on oe.user_id = r.owneruserid
  left join owner_last_activity ola on ola.user_id = oe.user_id
  where r.is_closed = 1
    and r.engagement_score > (
      select avg(s.engagement_score) + 2 * stddev_pop(s.engagement_score)
      from scored s
    )
),
-- Deduplicate in case of overlap and compute final ordering metrics
final_rank as (
  select
    fs.*,
    row_number() over (order by fs.engagement_score desc nulls last, fs.quality_index desc nulls last, fs.q_created desc) as global_rownum,
    dense_rank() over (partition by fs.owner_id order by fs.engagement_score desc nulls last) as owner_dense_rank
  from final_set fs
)
select
  fr.*
from final_rank fr
where
  -- Complicated predicate combining multiple signals
  (
    (fr.engagement_band in ('P90+', 'P75-90') and coalesce(fr.has_answers,0) = 1)
    or
    (fr.engagement_band = 'ClosedOutlier' and fr.is_closed = 1)
    or
    (fr.owner_rep_decile <= 3 and fr.pct_quality_month >= 0.8)
  )
  and not (
    fr.tag_count is null
    and fr.sum_tag_global_count is null
    and fr.avg_popularity_decile is null
  )
  and (
    fr.secs_to_first_answer_norm is null
    or fr.secs_to_first_answer_norm >= 0
  )
order by
  fr.global_rownum
limit 500;