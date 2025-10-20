-- {"query": "7049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2063} 
with
-- recent activity per post including gaps and tag parsing
posts_cte as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.title,
    p.tags,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    coalesce(p.answercount,0) as answercount,
    -- explode tags into rows-ish using recursive split (portable SQL)
    case when p.tags is null then '' else p.tags end as raw_tags
  from posts p
  where p.creationdate >= now() - interval '5 years'
),
-- recursively split tags string like '<sql><performance>' into tag tokens
tag_split (post_id, tags_str, token, rest) as (
  select id, raw_tags,
    null::varchar,
    case when raw_tags like '<%>%'
         then raw_tags
         else null end
  from posts_cte
  union all
  select
    post_id,
    rest,
    substring(rest from 2 for (coalesce(NULLIF(strpos(rest,'><'),0), strpos(rest,'>')) - 2)) as token,
    case
      when strpos(rest,'><')>0 then substring(rest from strpos(rest,'><')+2)
      when strpos(rest,'>')>0 then substring(rest from strpos(rest,'>')+1)
      else null
    end as rest
  from tag_split
  where rest is not null and rest <> ''
),
-- aggregate tag popularity and length metrics
tag_stats as (
  select
    lower(token) as tag,
    count(distinct post_id) as question_count,
    avg(length(token)) as avg_tag_len,
    max(length(token)) as max_tag_len
  from tag_split
  where token is not null and token <> ''
  group by lower(token)
),
-- user summary with window functions across their recent posts
user_posts as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    p.id as post_id,
    p.posttypeid,
    p.creationdate as post_created,
    p.score,
    p.viewcount,
    row_number() over (partition by u.id order by p.creationdate desc) as rn_desc,
    rank() over (partition by u.id order by p.score desc) as score_rank,
    count(*) over (partition by u.id) as posts_in_window
  from users u
  left join posts p on p.owneruserid = u.id and p.creationdate >= now() - interval '5 years'
  where u.creationdate <= now()
),
-- identify suspicious posts: high score but low views OR vice versa, include null checks
suspicious_posts as (
  select
    p.id,
    p.title,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    case
      when p.viewcount is null or p.viewcount = 0 then 999999
      else (p.score::float / nullif(p.viewcount,0))
    end as score_per_view,
    case
      when p.score > 100 and coalesce(p.viewcount,0) < 50 then 'HighScoreLowViews'
      when p.viewcount > 100000 and p.score < 0 then 'ManyViewsNegScore'
      else 'Normal'
    end as anomaly_type
  from posts p
  where p.creationdate >= now() - interval '2 years'
),
-- correlative subquery: for each question, compute median answer score using a correlated subquery
question_answer_medians as (
  select
    q.id as question_id,
    q.title,
    q.tags,
    q.owneruserid,
    (select percentile_cont(0.5) within group (order by a.score)
     from posts a
     where a.parentid = q.id and a.posttypeid = 2) as median_answer_score,
    (select count(*) from posts a where a.parentid = q.id and a.posttypeid = 2) as answer_count
  from posts q
  where q.posttypeid = 1 and q.creationdate >= now() - interval '3 years'
),
-- combine votes summary with conditional aggregation and set operator usage
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started_total
  from votes v
  where v.creationdate >= now() - interval '4 years'
  group by v.postid
),
-- union articles: select top-performing and bottom-performing posts for stress testing
top_and_bottom as (
  select p.id, p.title, p.score, p.viewcount, 'TOP' as bucket
  from posts p
  where p.creationdate >= now() - interval '5 years'
  order by p.score desc nulls last, p.viewcount desc nulls last
  limit 100
  union all
  select p.id, p.title, p.score, p.viewcount, 'BOTTOM' as bucket
  from posts p
  where p.creationdate >= now() - interval '5 years'
  order by p.score asc nulls last, p.viewcount asc nulls last
  limit 100
),
-- final heavy aggregation joining many CTEs together, include complicated predicates and NULL coalescing
final as (
  select
    p.id as post_id,
    p.title,
    p.posttypeid,
    u.id as owner_id,
    u.displayname,
    u.reputation,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(qa.answer_count,0) as answer_count,
    qa.median_answer_score,
    ts.tag,
    ts.question_count,
    ts.avg_tag_len,
    sp.anomaly_type,
    ub.bucket,
    -- string-heavy expression: normalized title fingerprint
    lower(regexp_replace(coalesce(p.title,''), '[^a-z0-9]+', '-', 'g')) as title_fingerprint,
    -- complex score normalization with NULL safety and logarithms
    case
      when p.viewcount is null or p.viewcount = 0 then null
      else round( ( (coalesce(p.score,0) + coalesce(va.upvotes,0) - coalesce(va.downvotes,0))::numeric
             / (1 + ln(1 + GREATEST(p.viewcount,1))) )::numeric, 6)
    end as normalized_impact,
    -- windowed percentile per tag
    percentile_cont(0.9) within group (order by p.score) over (partition by ts.tag) as tag_90th_score,
    -- complicated null logic combining multiple sources for last_activity
    coalesce(p.lastactivitydate, ph.max_history_date, u.lastaccessdate, p.creationdate) as effective_last_activity
  from posts p
  left join users u on u.id = p.owneruserid
  left join vote_agg va on va.postid = p.id
  left join question_answer_medians qa on qa.question_id = p.id
  left join tag_split t on t.post_id = p.id
  left join tag_stats ts on ts.tag = lower(t.token)
  left join suspicious_posts sp on sp.id = p.id
  left join top_and_bottom ub on ub.id = p.id
  left join (
    select postid, max(creationdate) as max_history_date
    from posthistory
    where creationdate >= now() - interval '6 years'
    group by postid
  ) ph on ph.postid = p.id
  where p.creationdate >= now() - interval '5 years'
)
-- final selection with ordering, grouping, and set operator application to force planner complexity
select
  f.post_id,
  f.title,
  f.posttypeid,
  f.owner_id,
  f.displayname,
  f.reputation,
  f.upvotes,
  f.downvotes,
  f.favorites,
  f.answer_count,
  f.median_answer_score,
  f.tag,
  f.question_count,
  f.avg_tag_len,
  f.anomaly_type,
  f.bucket,
  f.title_fingerprint,
  f.normalized_impact,
  f.tag_90th_score,
  f.effective_last_activity
from final f
where
  -- complicated predicate: include posts that either belong to a popular tag OR have unusual score/view signature,
  -- but exclude community-wiki and posts with null owners unless they are in TOP bucket
  (
    (f.question_count > 500 or f.tag in ('sql','performance','postgresql'))
    or f.anomaly_type <> 'Normal'
  )
  and (
    (f.owner_id is not null and f.owner_id <> -1)
    or f.bucket = 'TOP'
  )
  and (f.normalized_impact is not null or f.median_answer_score is not null)
order by
  -- multi-criteria ordering with NULLS LAST and expression sorting
  coalesce(f.normalized_impact, -999999) desc,
  f.tag_90th_score desc nulls last,
  f.question_count desc nulls last,
  f.reputation desc nulls last
limit 500;