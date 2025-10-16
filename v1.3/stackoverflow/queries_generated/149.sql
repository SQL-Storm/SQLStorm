-- {"query": "149.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2234} 
with
-- explode tags from question posts
question_tags as (
  select p.id as post_id,
         p.owneruserid,
         trim(t) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><')) as t
  ) s
  where p.posttypeid = 1 and p.tags is not null
),

-- aggregate per question: top answer score, answer count (including deleted via parent link absence), title length, recent activity lag
question_stats as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as q_created,
         coalesce(q.answercount, 0) as answer_count,
         coalesce(q.viewcount, 0) as view_count,
         length(coalesce(q.title, '')) as title_len,
         max(a.score) filter (where a.posttypeid = 2) over (partition by q.id) as top_answer_score,
         (now() - q.lastactivitydate) as inactive_interval
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id, q.owneruserid, q.creationdate, q.answercount, q.viewcount, q.title, q.lastactivitydate
),

-- per-user aggregates: counts, reputation, badges breakdown, medians and windows
user_base as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         coalesce(u.views,0) as profile_views,
         coalesce(u.upvotes,0) as upvotes,
         coalesce(u.downvotes,0) as downvotes,
         coalesce(u.accountid, -1) as account_id,
         count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
         count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
         sum(p.score) filter (where p.posttypeid in (1,2)) as post_score_sum,
         count(b.id) as badge_count,
         max(case when b.class = 1 then 1 else 0 end) as has_gold,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.views, u.upvotes, u.downvotes, u.accountid
),

-- compute per-user median answer score (correlated subquery style inside agg via array)
user_answer_median as (
  select u.id as user_id,
         -- median by ordering array of scores
         (
           select avg(x)::numeric
           from (
             select a.score::numeric
             from posts a
             where a.posttypeid = 2 and a.owneruserid = u.id
             order by a.score
             limit 2 - (select count(*) from posts a2 where a2.posttypeid = 2 and a2.owneruserid = u.id) % 2
             offset floor((select count(*) from posts a3 where a3.posttypeid = 2 and a3.owneruserid = u.id)::numeric / 2)
           ) t(x)
         ) as median_answer_score,
         -- variance of answer scores using window/aggregate
         coalesce( (select var_pop(score) from posts pa where pa.posttypeid = 2 and pa.owneruserid = u.id), 0) as var_answer_score
  from users u
),

-- tag affinity per user: pick most frequent tag and its share
user_tag_affinity as (
  select qt.owneruserid as user_id,
         t.tag,
         count(*) as tag_count,
         rank() over (partition by qt.owneruserid order by count(*) desc, t.tag) as rnk,
         sum(count(*)) over (partition by qt.owneruserid) as total_tagged_questions
  from question_tags qt
  group by qt.owneruserid, t.tag
  order by qt.owneruserid, tag_count desc
),

-- recent activity window: last 90 days posts and votes
recent_activity as (
  select u.id as user_id,
         count(distinct p.id) filter (where p.creationdate >= now() - interval '90 days') as recent_posts,
         count(v.id) filter (where v.creationdate >= now() - interval '90 days') as recent_votes,
         coalesce(sum(v.bountyamount) filter (where v.creationdate >= now() - interval '365 days'),0) as recent_bounties
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.userid = u.id
  group by u.id
),

-- combine base metrics with medians etc.
user_metrics as (
  select ub.*,
         uam.median_answer_score,
         uam.var_answer_score,
         ra.recent_posts,
         ra.recent_votes,
         ra.recent_bounties
  from user_base ub
  left join user_answer_median uam on uam.user_id = ub.user_id
  left join recent_activity ra on ra.user_id = ub.user_id
),

-- pick candidate users: enough posts and presence of tags
candidates as (
  select um.*,
         coalesce(utf.tag, '(none)') as top_tag,
         coalesce(utf.tag_count, 0) as top_tag_count,
         coalesce(utf.total_tagged_questions, 0) as tag_total_questions
  from user_metrics um
  left join (
    select user_id, tag, tag_count, total_tagged_questions
    from (
      select owneruserid as user_id, tag, count(*) as tag_count,
             sum(count(*)) over (partition by owneruserid) as total_tagged_questions,
             row_number() over (partition by owneruserid order by count(*) desc) as rn
      from question_tags
      group by owneruserid, tag
    ) s
    where rn = 1
  ) utf on utf.user_id = um.user_id
  where (um.q_count + um.a_count) >= 5 -- minimal footprint
),

-- compute per-question complex score combining views, top answer, recency, title length and tag popularity (correlated)
question_complex as (
  select qs.*,
         coalesce(qt_pop.popularity, 0) as tag_popularity_score,
         -- penalize long titles, reward top answers and views (nonlinear)
         (log(1 + greatest(qs.view_count,0)) * coalesce(qs.top_answer_score,0)
          + sqrt(1 + qs.answer_count) * 10
          - least(qs.title_len, 200) * 0.3
          - extract(epoch from qs.inactive_interval)/86400 * 0.1
         ) as complexity_score
  from question_stats qs
  left join (
    select tag, sum(count) as popularity
    from tags t
    group by tag
  ) qt_pop on qt_pop.tag = (
    select unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><'))
    from posts p where p.id = qs.question_id limit 1
  )
)

select
  c.user_id,
  c.displayname,
  c.reputation,
  c.q_count,
  c.a_count,
  c.post_score_sum,
  round(coalesce(c.median_answer_score,0)::numeric,2) as median_answer_score,
  round(coalesce(c.var_answer_score,0)::numeric,2) as var_answer_score,
  c.top_tag,
  c.top_tag_count,
  c.tag_total_questions,
  c.recent_posts,
  c.recent_votes,
  c.recent_bounties,
  c.badge_count,
  c.has_gold,
  c.bronze_badges,
  -- compute a synthetic influence metric using window functions
  rank() over (order by (c.reputation * 0.5 + coalesce(c.post_score_sum,0) * 0.2 + coalesce(c.recent_posts,0) * 5 + coalesce(c.badge_count,0) * 2) desc) as influence_rank,
  -- correlated subquery: pick 3 most complex questions by this user
  (
    select json_agg(qs2.question_id order by qs2.complexity_score desc)
    from question_complex qs2
    where qs2.asker_id = c.user_id
    limit 1
  ) as top_questions_ids,
  -- existence checks and boolean flags
  case when exists (select 1 from badges b2 where b2.userid = c.user_id and b2.class = 1) then true else false end as has_any_gold,
  case when c.recent_posts > 0 or c.recent_votes > 0 then true else false end as active_recently,
  -- string manipulation: anonymized contact token
  concat('u', c.user_id, '_', substring(md5(coalesce(c.displayname,'') || coalesce(c.emailhash,'')) for 6)) as anonymized_token
from candidates c
where coalesce(c.reputation,0) > 50
  and (coalesce(c.a_count,0) >= 2 or coalesce(c.q_count,0) >= 2)
  and (
    coalesce(c.top_tag_count,0) >= 1
    or exists (
      select 1 from posts p where p.owneruserid = c.user_id and p.body ilike '%performance%' limit 1
    )
  )
order by influence_rank asc, c.reputation desc
limit 100;