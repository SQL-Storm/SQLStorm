-- {"query": "179.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1861} 
with
-- explode tags into rows
tag_map as (
  select p.id as post_id,
         lower(trim(both '<>' from tag)) as tag
  from posts p
  cross join lateral (
    select regexp_split_to_table(substring(p.tags from 2 for char_length(p.tags)-2), '><') as tag
  ) t
  where p.posttypeid = 1 and p.tags is not null
),
-- recent questions windowed and annotated
recent_q as (
  select p.*,
         row_number() over (partition by p.owneruserid order by p.creationdate desc) as rn_per_user,
         rank() over (order by p.viewcount desc nulls last, p.score desc) as popularity_rank,
         coalesce(p.answercount,0) as answers_reported,
         -- string tricks: title fingerprint
         lower(replace(regexp_replace(coalesce(p.title,''), '[^a-z0-9 ]', '','gi'), '  ', ' ')) as title_fingerprint
  from posts p
  where p.posttypeid = 1
),
-- aggregate answers info
answer_stats as (
  select a.parentid as question_id,
         count(*) filter (where a.creationdate >= q.creationdate and a.creationdate < q.creationdate + interval '30 days') as answers_in_30d,
         count(*) as total_answers,
         avg(coalesce(a.score,0)) as avg_answer_score,
         max(a.score) as max_answer_score,
         sum(case when a.owneruserid is null then 1 else 0 end) as anonymous_answers
  from posts a
  left join posts q on q.id = a.parentid
  where a.posttypeid = 2
  group by a.parentid
),
-- votes per post with correlated subquery for recent upvotes
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as vote_net,
         count(*) filter (where v.votetypeid = 2) as upvotes,
         count(*) filter (where v.votetypeid = 3) as downvotes,
         (select count(*) from votes v2 where v2.postid = v.postid and v2.creationdate >= current_date - interval '7 days' and v2.votetypeid = 2) as recent_upvotes_7d
  from votes v
  group by v.postid
),
-- last comment per question (correlated)
last_comment as (
  select c.postid,
         (select c2.id from comments c2 where c2.postid = c.postid order by c2.creationdate desc limit 1) as last_comment_id,
         (select c3.creationdate from comments c3 where c3.postid = c.postid order by c3.creationdate desc limit 1) as last_comment_date,
         (select substring(c4.text from 1 for 120) from comments c4 where c4.postid = c.postid order by c4.creationdate desc limit 1) as last_comment_excerpt
  from comments c
  group by c.postid
),
-- user derived stats
user_stats as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         coalesce(b.badge_gold,0) as gold,
         coalesce(b.badge_silver,0) as silver,
         coalesce(b.badge_bronze,0) as bronze,
         -- activity recency and access gap
         greatest(0, date_part('day', now() - u.lastaccessdate)) as days_since_last_access
  from users u
  left join (
    select userId,
           sum(case when class = 1 then 1 else 0 end) as badge_gold,
           sum(case when class = 2 then 1 else 0 end) as badge_silver,
           sum(case when class = 3 then 1 else 0 end) as badge_bronze
    from badges
    group by userId
  ) b on b.userId = u.id
),
-- questions union with synthetic "community" row for set ops demonstration
questions_union as (
  select q.*
  from recent_q q
  where q.creationdate >= current_date - interval '365 days'
  union
  select p.*
  from posts p
  where p.posttypeid = 1 and p.id in (
    select id from posts order by coalesce(viewcount,0) desc limit 5
  )
),
-- combine everything
combined as (
  select
    qu.id as question_id,
    qu.title,
    qu.owneruserid,
    us.displayname as owner_name,
    coalesce(us.reputation,0) as owner_reputation,
    qu.creationdate,
    qu.lastactivitydate,
    qu.score as question_score,
    coalesce(va.vote_net,0) as vote_net,
    coalesce(as_.answers_in_30d,0) as answers_in_30d,
    coalesce(as_.total_answers,0) as total_answers,
    coalesce(va.recent_upvotes_7d,0) as recent_upvotes_7d,
    tm.tag,
    lc.last_comment_date,
    lc.last_comment_excerpt,
    -- derived complexity metric mixing many factors
    (
      1.0 * coalesce(qu.viewcount,0) / nullif(greatest(1, coalesce(qu.answercount,0)),0)
      + 50 * coalesce(qu.score,0)
      + 200 * coalesce(va.recent_upvotes_7d,0)
      - 100 * coalesce(as_.anonymous_answers,0)
      + 10 * coalesce(us.reputation,0)::numeric / nullif(us.days_since_last_access,1)
    ) as complexity_score,
    -- text expression showing tag summary
    case
      when tm.tag is null then 'untagged'
      when tm.tag = 'sql' then 'sql-special'
      else tm.tag
    end as tag_label,
    -- null logic example
    coalesce(qu.title, '[no title]') || ' [' || coalesce(tm.tag,'none') || ']' as title_with_tag
  from questions_union qu
  left join answer_stats as_ on as_.question_id = qu.id
  left join vote_agg va on va.postid = qu.id
  left join tag_map tm on tm.post_id = qu.id
  left join last_comment lc on lc.postid = qu.id
  left join user_stats us on us.user_id = qu.owneruserid
)
select
  c.question_id,
  left(coalesce(c.title,'[no title]'),120) as title_excerpt,
  c.owner_name,
  c.owner_reputation,
  c.creationdate,
  c.lastactivitydate,
  c.question_score,
  c.vote_net,
  c.total_answers,
  c.answers_in_30d,
  c.recent_upvotes_7d,
  c.tag_label,
  count(distinct c.tag) over (partition by c.question_id) as distinct_tag_count,
  first_value(c.last_comment_date) over (partition by c.question_id order by c.last_comment_date desc nulls last) as most_recent_comment,
  c.last_comment_excerpt,
  round(c.complexity_score::numeric,2) as complexity_score,
  dense_rank() over (order by c.complexity_score desc) as complexity_rank
from combined c
where
  -- complicated predicate: mix of null checks, text checks, regex and numeric windows
  (c.owner_reputation > 1000 or c.question_score >= 5 or c.recent_upvotes_7d >= 2)
  and (c.tag_label not ilike '%meta%' or c.tag_label = 'sql-special')
  and (c.title_with_tag ~* 'error|exception|fail|problem' or c.complexity_score > 1000)
  and coalesce(c.last_comment_date, now()) >= now() - interval '400 days'
order by complexity_score desc NULLS LAST, distinct_tag_count desc, question_id
limit 50;