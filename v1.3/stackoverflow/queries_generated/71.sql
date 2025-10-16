-- {"query": "71.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1921} 
with
-- recent active questions with parsed tag counts and heuristics
recent_questions as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    coalesce(p.viewcount,0) as viewcount,
    coalesce(p.score,0) as score,
    coalesce(p.answercount,0) as answercount,
    coalesce(p.favoritecount,0) as favoritecount,
    p.tags,
    -- derive normalized tag list (array) and tag count (defensive for null)
    case when p.tags is null then array[]::text[]
         else string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')
    end as tag_array,
    case when p.tags is null then 0 else array_length(string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><'),1) end as tag_count
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '365 days'
),

-- compute user aggregates and recency metrics
user_stats as (
  select
    u.id as user_id,
    u.reputation,
    u.creationdate as user_creation,
    coalesce(u.views,0) as profile_views,
    coalesce(u.upvotes,0) as upvotes,
    coalesce(u.downvotes,0) as downvotes,
    -- number of questions and answers in last year (correlated subqueries)
    (select count(*) from posts p2 where p2.owneruserid = u.id and p2.posttypeid = 1 and p2.creationdate >= now() - interval '365 days') as q_last_year,
    (select count(*) from posts p2 where p2.owneruserid = u.id and p2.posttypeid = 2 and p2.creationdate >= now() - interval '365 days') as a_last_year,
    -- time since last access in days
    extract(epoch from (now() - u.lastaccessdate))/86400.0 as days_since_access
  from users u
),

-- heavy windowing: top tags (by question count) across recent questions
tag_counts as (
  select
    tag,
    count(*) as questions_with_tag,
    dense_rank() over (order by count(*) desc) as rnk
  from (
    select unnest(tag_array) as tag
    from recent_questions
  ) t
  group by tag
),

-- compute per-question leaderboards and complex scoring
question_scores as (
  select
    rq.*,
    us.user_id,
    us.reputation,
    us.q_last_year,
    us.a_last_year,
    us.days_since_access,
    -- popularity score: weighted non-linear mix with null-safe operations
    ( sqrt(coalesce(rq.viewcount,0)) * 0.6
      + ln(GREATEST(coalesce(rq.score,0),1)) * 1.2
      + (coalesce(rq.answercount,0) * 2.5)
      + (coalesce(rq.favoritecount,0) * 3.0)
      + (case when rq.tag_count = 0 then -5 else 0 end)
    ) as popularity_index,
    -- expertise score: based on owner's reputation and recent contributions
    (coalesce(us.reputation,0) * 0.002 + coalesce(us.a_last_year,0) * 0.5 - coalesce(us.days_since_access,0) * 0.01) as expertise_index,
    -- tag rarity: average inverse tag frequency (use LEFT JOIN to tag_counts)
    (select avg(1.0 / nullif(tc.questions_with_tag,0))
     from unnest(rq.tag_array) ttag
     left join tag_counts tc on tc.tag = ttag
    ) as avg_inverse_tag_freq
  from recent_questions rq
  left join user_stats us on us.user_id = rq.owneruserid
),

-- detect suspicious or unusual posts via correlated subqueries and anti-joins
suspicious_signals as (
  select
    qs.id,
    -- recent high-score low-views (possible voting anomalies)
    case when qs.score >= 10 and qs.viewcount < 100 then 1 else 0 end as high_score_low_views,
    -- multiple answers by same owner (self-answers) within short time window
    (select count(*) from posts p2 where p2.owneruserid = qs.owneruserid and p2.posttypeid = 2 and p2.parentid in
       (select id from posts p3 where p3.owneruserid = qs.owneruserid and p3.posttypeid = 1 and p3.creationdate between qs.creationdate - interval '7 days' and qs.creationdate + interval '7 days')
    ) as self_answer_count_window,
    -- existence of recent comments containing "thanks", "plz", or "urgent" (text search via ilike)
    (select count(*) from comments c where c.postid = qs.id and (c.text ilike '%thank%' or c.text ilike '%plz%' or c.text ilike '%urgent%') ) as rude_or_thanks_comments
  from question_scores qs
),

-- combined enriched dataset
enriched as (
  select
    qs.*,
    ss.high_score_low_views,
    ss.self_answer_count_window,
    ss.rude_or_thanks_comments,
    -- composite anomaly score with NULL-aware math
    (coalesce(qs.popularity_index,0) * 0.4 + coalesce(qs.expertise_index,0) * -0.2 + coalesce(qs.avg_inverse_tag_freq,0) * 10
     + coalesce(ss.high_score_low_views,0) * 15 + coalesce(ss.self_answer_count_window,0) * 5 + coalesce(ss.rude_or_thanks_comments,0) * 2
    ) as anomaly_score
  from question_scores qs
  left join suspicious_signals ss on ss.id = qs.id
)

select
  e.id as question_id,
  e.title,
  e.creationdate,
  e.owneruserid,
  e.reputation as owner_reputation,
  e.viewcount,
  e.score,
  e.answercount,
  e.tag_count,
  -- format tags into a single string with length caps and ellipsis
  case when e.tags is null then '(none)'
       when length(e.tags) > 200 then left(e.tags,200) || '...'
       else e.tags
  end as tags_preview,
  round(e.popularity_index::numeric,3) as popularity_index,
  round(e.expertise_index::numeric,3) as expertise_index,
  round(e.avg_inverse_tag_freq::numeric,6) as avg_inv_tag_freq,
  e.high_score_low_views,
  e.self_answer_count_window,
  e.rude_or_thanks_comments,
  round(e.anomaly_score::numeric,4) as anomaly_score,
  -- windowed rank within same tag_count bucket: high anomaly first
  rank() over (partition by e.tag_count order by e.anomaly_score desc NULLS LAST) as tag_bucket_anomaly_rank,
  -- running aggregates: running average anomaly across creation dates
  avg(e.anomaly_score) over (order by e.creationdate rows between 30 preceding and current row) as running_avg_anomaly_30days,
  -- last edit and last activity correlation (complex correlated subquery)
  (select ph.creationdate from posthistory ph where ph.postid = e.id and ph.posthistorytypeid in (4,5,6,24) order by ph.creationdate desc limit 1) as last_edit_date,
  (select po.lastactivitydate from posts po where po.id = e.id) as last_activity_date,
  -- boolean-ish string expressing freshness vs activity
  case
    when (select po.lastactivitydate from posts po where po.id = e.id) is null then 'no-activity'
    when (select po.lastactivitydate from posts po where po.id = e.id) > e.creationdate + interval '90 days' then 'stale'
    when (select po.lastactivitydate from posts po where po.id = e.id) > now() - interval '7 days' then 'hot'
    else 'active'
  end as activity_status
from enriched e
-- join to find questions that mention a top-10 tag lexically in title (complex predicate + set operator)
left join (
  select tag from tag_counts where rnk <= 10
) top_tags on position(top_tags.tag in coalesce(e.title,'')) > 0
where
  -- filter: include either high anomaly or hot or contains top tag, but exclude community-owned nudges
  (e.anomaly_score > 20 OR e.creationdate >= now() - interval '30 days' OR top_tags.tag is not null)
  and not exists (select 1 from posts p_ex where p_ex.id = e.id and p_ex.communityowneddate is not null)
order by
  e.anomaly_score desc nulls last,
  e.popularity_index desc
limit 250;