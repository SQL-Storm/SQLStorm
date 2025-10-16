-- {"query": "79.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2093} 
with
-- recent active questions with parsed tag array and basic metrics
recent_q as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    p.score,
    coalesce(p.viewcount,0) as viewcount,
    coalesce(p.answercount,0) as answercount,
   -- normalize tags into a set-like space: tag tokens without angle brackets
    case when p.tags is null then array[]::varchar[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_list
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '365 days'
),
-- top answerers in the last year by score, with some windowed rank
answerers as (
  select
    a.owneruserid as userid,
    count(*) filter (where a.score > 0) as positive_answers,
    sum(coalesce(a.score,0)) as total_answer_score,
    avg(coalesce(a.score,0)) as avg_answer_score,
    row_number() over (order by sum(coalesce(a.score,0)) desc) as rnk
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= now() - interval '365 days'
    and a.owneruserid is not null
  group by a.owneruserid
),
-- compute for each question: accepted answer info, duplicate links, and last meaningful activity
q_meta as (
  select
    q.id,
    q.acceptedanswerid,
    q.creationdate,
    q.owneruserid,
    q.score,
    q.viewcount,
    q.answercount,
    q.tag_list,
    -- boolean heuristics for community attention
    exists (
      select 1 from postlinks pl where pl.postid = q.id and pl.linktypeid = 3
    ) as has_duplicate_link,
    (select max(ph.creationdate) from posthistory ph where ph.postid = q.id) as last_history,
    (select max(c.creationdate) from comments c where c.postid = q.id) as last_comment
  from recent_q q
),
-- aggregate votes for candidate posts with complex conditional weighting (decay and type-based)
vote_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    sum(
      case
        when v.votetypeid in (2,5) then greatest(1, 100 - extract(day from (now() - v.creationdate)))::numeric
        when v.votetypeid = 3 then -50
        when v.votetypeid in (12,10) then -200
        else 0
      end
    ) as weighted_vote_score
  from votes v
  where v.creationdate >= now() - interval '730 days'
  group by v.postid
),
-- user enrichment: recent badge counts, recency, and activity windows
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(b.badge_count,0) as badge_count,
    coalesce(b.gold,0) as gold_badges,
    coalesce(b.silver,0) as silver_badges,
    coalesce(b.bronze,0) as bronze_badges,
    -- activity score combining reputation and recency
    (u.reputation::numeric * 0.6 + (extract(epoch from (now() - u.lastaccessdate))/86400 + 1)::numeric * -0.1 + coalesce(b.badge_count,0) * 2) as activity_score
  from users u
  left join (
    select
      userId,
      count(*) as badge_count,
      sum(case when class=1 then 1 else 0 end) as gold,
      sum(case when class=2 then 1 else 0 end) as silver,
      sum(case when class=3 then 1 else 0 end) as bronze
    from badges
    group by userId
  ) b on b.userId = u.id
),
-- candidate ranking: combine question metrics, votes, and owner quality; include correlated subquery to fetch accepted answer score
candidates as (
  select
    qm.id as question_id,
    qm.title,
    qm.creationdate,
    qm.owneruserid,
    qm.score as q_score,
    qm.viewcount,
    qm.answercount,
    qm.has_duplicate_link,
    qm.tag_list,
    va.upvotes,
    va.downvotes,
    va.favorites,
    va.weighted_vote_score,
    us.activity_score as owner_activity,
    -- correlated subquery to compute accepted answer aggregate if present
    (
      select coalesce(sum(coalesce(a.score,0)) + count(*) * 2,0)
      from posts a
      where a.id = qm.acceptedanswerid
    ) as accepted_answer_value,
    -- distance-like metric: age in days
    greatest(1, extract(epoch from (now() - qm.creationdate))/86400) as age_days,
    -- entropy-like tag diversity: number of tags and a simple hash to vary distribution
    cardinality(qm.tag_list) as tag_count,
    (abs(hashtext(coalesce(qm.title,''))) % 97) as title_hash_mod
  from q_meta qm
  left join vote_agg va on va.postid = qm.id
  left join user_stats us on us.id = qm.owneruserid
),
-- final scoring with a complicated expression combining many elements, NULL logic, windows, and ties resolution
scored as (
  select
    c.*,
    -- base score: weighted votes scaled by recency and owner quality, penalize duplicates and long age
    (
      coalesce(c.weighted_vote_score,0) * (1 + coalesce(c.owner_activity,0)/100.0)
      + coalesce(c.accepted_answer_value,0) * 0.5
      + log(greatest(1,c.viewcount)) * 1.2
      - (case when c.has_duplicate_link then 150 else 0 end)
      - ln(greatest(1,c.age_days)) * 10
      + (c.tag_count::numeric * 3)
      + (case when c.title_hash_mod < 20 then 10 else 0 end)
    ) as raw_score,
    -- compute percentile over partition by tag_count buckets
    percent_rank() over (partition by c.tag_count order by (
      coalesce(c.weighted_vote_score,0) * (1 + coalesce(c.owner_activity,0)/100.0)
      + coalesce(c.accepted_answer_value,0) * 0.5
      + log(greatest(1,c.viewcount)) * 1.2
      - (case when c.has_duplicate_link then 150 else 0 end)
      - ln(greatest(1,c.age_days)) * 10
    ) desc) as bucket_percentile,
    -- tie-breaker: dense rank using composite of raw_score and favorite votes
    dense_rank() over (order by (
      coalesce(c.weighted_vote_score,0) * 1000 + coalesce(c.favorites,0) * 500 + coalesce(c.q_score,0) * 50
    ) desc) as dense_rank_score
  from candidates c
),
-- final selection: pick top N per tag (demonstrating set operators and union)
top_per_tag as (
  select distinct on (t.tag, s.dense_rank_score)
    t.tag,
    s.question_id,
    s.title,
    s.raw_score,
    s.bucket_percentile,
    s.dense_rank_score
  from scored s
  cross join lateral (
    -- unnest tags to produce one row per tag; keep first 3 tags to limit explosion
    select unnest(s.tag_list) as tag
  ) t
  where t.tag is not null
  order by t.tag, s.raw_score desc, s.question_id
),
-- union an alternate set: high raw_score questions regardless of tags, limited and offset to stress planner
top_overall as (
  select
    '<<overall>>'::varchar as tag,
    question_id,
    title,
    raw_score,
    bucket_percentile,
    dense_rank_score
  from scored
  where raw_score is not null
  order by raw_score desc, question_id
  limit 200 offset 10
)
select
  tp.tag,
  tp.question_id,
  tp.title,
  round(tp.raw_score::numeric,2) as score,
  round(tp.bucket_percentile::numeric,4) as pct,
  tp.dense_rank_score,
  -- enrich with one more correlated scalar: top 3 answerer names who answered this question recently (string concat)
  coalesce(
    (
      select string_agg(distinct u.displayname || ':' || coalesce(a.score::text,'0'), ' | ' order by sum(coalesce(a.score,0)) desc)
      from posts a
      left join users u on u.id = a.owneruserid
      where a.parentid = tp.question_id and a.posttypeid = 2
      group by u.displayname
      order by sum(coalesce(a.score,0)) desc
      limit 3
    ), 'NO_ANSWERS'
  ) as top_answerers_snippet
from (
  select * from top_per_tag
  union
  select * from top_overall
) tp
order by tp.tag nulls last, tp.raw_score desc, tp.question_id
limit 500;