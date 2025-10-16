-- {"query": "85.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2301} 
with
-- Top users by complex reputation velocity and diversification
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(u.views,0) as views,
    coalesce(u.upvotes,0) as upvotes,
    coalesce(u.downvotes,0) as downvotes,
    -- days since creation (avoid division by zero)
    greatest(extract(epoch from (now() - u.creationdate))/86400.0, 1.0) as days_alive,
    -- reputation per day with null-safe math and noise smoothing
    (u.reputation::numeric / greatest(extract(epoch from (now() - u.creationdate))/86400.0, 7.0))::numeric(12,4) as rep_per_week_equiv,
    -- engagement score combining views/upvotes/downvotes with log scaling
    (ln(1+coalesce(u.views,0)) * 0.4 + ln(1+coalesce(u.upvotes,0)) * 0.5 - ln(1+coalesce(u.downvotes,0)) * 0.1)::numeric(12,6) as engagement_index
  from users u
),
-- Questions with enriched tag arrays and score normalization
question_base as (
  select
    p.id,
    p.title,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.tags,
    -- parse tags from '<tag1><tag2>' format into array (Postgres style)
    case when p.tags is null then '{}'::text[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_array,
    -- heuristic popularity
    (coalesce(p.score,0) * 3 + coalesce(p.viewcount,0)/100 + coalesce(p.answercount,0) * 5 + coalesce(p.favoritecount,0) * 10) as raw_pop
  from posts p
  where p.posttypeid = 1
),
-- Answers with link to parent question and acceptance flag
answer_base as (
  select
    a.id,
    a.parentid as questionid,
    a.owneruserid,
    a.creationdate,
    a.score,
    a.body,
    case when q.acceptedanswerid = a.id then true else false end as is_accepted
  from posts a
  left join posts q on q.id = a.parentid
  where a.posttypeid = 2
),
-- windowed aggregates per question and per user
question_metrics as (
  select
    q.id,
    q.title,
    q.owneruserid,
    q.creationdate,
    q.tag_array,
    q.raw_pop,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    -- counts of answers and accepted answers via correlated subquery (exists and counts)
    (select count(*) from posts a where a.parentid = q.id and a.posttypeid = 2) as answers_count,
    (select count(*) from posts a where a.parentid = q.id and a.posttypeid = 2 and a.id = q.acceptedanswerid) as accepted_count,
    -- average answer score (null-safe)
    (select avg(a.score) from posts a where a.parentid = q.id and a.posttypeid = 2) as avg_answer_score,
    -- time-to-first-answer in seconds (correlated)
    (select extract(epoch from min(a.creationdate) - q.creationdate) from posts a where a.parentid = q.id and a.posttypeid = 2) as secs_to_first_answer,
    -- latest activity by any action from posts/comments/votes
    greatest(
      coalesce(q.lastactivitydate, q.lasteditdate, q.creationdate),
      coalesce(
        (select max(ph.creationdate) from posthistory ph where ph.postid = q.id),
        q.creationdate
      ),
      coalesce(
        (select max(c.creationdate) from comments c where c.postid = q.id),
        q.creationdate
      )
    ) as computed_last_activity
  from question_base q
),
-- tag popularity derived from question metrics (unnest tags)
tags_expanded as (
  select
    t.tag,
    count(distinct q.id) as questions_with_tag,
    sum(coalesce(q.raw_pop,0)) as tag_raw_pop,
    avg(coalesce(q.viewcount,0)) as avg_views,
    percentile_cont(0.5) within group (order by coalesce(q.score,0)) as median_score
  from question_metrics q
  cross join lateral unnest(q.tag_array) as t(tag)
  group by t.tag
),
-- per-user answers and question mix, windowed ranking and skewness
user_activity as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.days_alive,
    u.rep_per_week_equiv,
    u.engagement_index,
    coalesce(qs.questions_posted,0) as questions_posted,
    coalesce(ans.answers_posted,0) as answers_posted,
    -- ratio and diversification (protect against zero)
    case when coalesce(qs.questions_posted,0)+coalesce(ans.answers_posted,0) = 0 then 0
         else round( coalesce(ans.answers_posted,0)::numeric / (qs.questions_posted+ans.answers_posted)::numeric, 4) end as answer_ratio,
    -- badge diversity (distinct badge names)
    coalesce(b.badge_count,0) as badge_count,
    -- active tags count from their questions
    coalesce(ut.tag_count,0) as active_tag_count,
    -- last seen activity
    greatest(coalesce(u.lastaccessdate,u.creationdate), (select max(p.lastactivitydate) from posts p where p.owneruserid = u.id)) as last_seen
  from user_stats u
  left join (
    select owneruserid, count(*) as questions_posted
    from posts
    where posttypeid = 1
    group by owneruserid
  ) qs on qs.owneruserid = u.id
  left join (
    select owneruserid, count(*) as answers_posted
    from posts
    where posttypeid = 2
    group by owneruserid
  ) ans on ans.owneruserid = u.id
  left join (
    select userId, count(distinct name) as badge_count
    from badges
    group by userid
  ) b on b.userid = u.id
  left join (
    select p.owneruserid,
           count(distinct t.tag) as tag_count
    from posts p
    cross join lateral (
      case when p.tags is null then array[]::text[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end
    ) as tag_array(tag)
    cross join lateral unnest(tag_array) as t(tag)
    where p.posttypeid = 1
    group by p.owneruserid
  ) ut on ut.owneruserid = u.id
),
-- identify suspicious or high-latency posts via left joins and null logic
suspicious_posts as (
  select
    q.id,
    q.title,
    q.owneruserid,
    q.creationdate,
    q.raw_pop,
    q.viewcount,
    q.answercount,
    q.avg_answer_score,
    q.secs_to_first_answer,
    q.computed_last_activity,
    -- flag: high popularity but long time to first answer
    case when coalesce(q.raw_pop,0) > 1000 and (q.secs_to_first_answer is null or q.secs_to_first_answer > 86400) then 1 else 0 end as late_attention_flag,
    -- flag: lots of edits without owner activity
    case when (
      (select count(*) from posthistory ph where ph.postid = q.id and ph.userid is not null) > 5
      and (select max(ph.creationdate) from posthistory ph where ph.postid = q.id) > (select coalesce(max(p.lastactivitydate), q.creationdate) from posts p where p.owneruserid = q.owneruserid)
    ) then 1 else 0 end as many_edits_without_owner
  from question_metrics q
),
-- combine and rank interesting items using window functions and set ops
ranked_activity as (
  select
    ua.*,
    row_number() over (order by ua.rep_per_week_equiv desc, ua.engagement_index desc) as user_rank_by_velocity,
    rank() over (order by ua.badge_count desc, ua.active_tag_count desc) as badge_rank,
    dense_rank() over (order by ua.answer_ratio desc) as answer_ratio_rank
  from user_activity ua
),
-- prepare final selection mixing top users, suspicious posts, and tag trends
final_union as (
  select
    'user' as kind,
    ra.id as entity_id,
    ra.displayname as short_title,
    null::text as details,
    ra.reputation as metric1,
    ra.rep_per_week_equiv as metric2,
    ra.engagement_index as metric3,
    ra.user_rank_by_velocity as ord
  from ranked_activity ra
  where ra.user_rank_by_velocity <= 50

  union

  select
    'post' as kind,
    sp.id as entity_id,
    left(sp.title,120) as short_title,
    concat('tags=', coalesce(array_to_string((select tag_array from question_base qb where qb.id=sp.id),','),''), ';avg_ans_score=', coalesce(sp.avg_answer_score::text,'NULL')) as details,
    coalesce(sp.raw_pop,0) as metric1,
    coalesce(sp.secs_to_first_answer,0) as metric2,
    coalesce(sp.viewcount,0) as metric3,
    row_number() over (order by sp.raw_pop desc nulls last) + 100 as ord
  from suspicious_posts sp
  where sp.late_attention_flag = 1 or sp.many_edits_without_owner = 1

  union

  -- top trending tags by combined popularity, limited
  select
    'tag' as kind,
    t.tag::int * 0 + row_number() over () as entity_id, -- synthetic id
    t.tag as short_title,
    concat('questions=', t.questions_with_tag, ';pop=', t.tag_raw_pop::bigint) as details,
    t.tag_raw_pop as metric1,
    t.avg_views as metric2,
    t.median_score as metric3,
    row_number() over (order by t.tag_raw_pop desc) + 200 as ord
  from tags_expanded t
  order by ord
)
select *
from final_union
order by ord, kind, metric1 desc
limit 500;