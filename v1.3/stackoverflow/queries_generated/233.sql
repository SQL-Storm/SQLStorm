-- {"query": "233.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3871} 
with
-- base question and answer sets with defensive tag parsing
questions as (
  select
    p.*,
    coalesce(
      case when p.tags is null or p.tags = '' then null
           else string_to_array(substring(p.tags,2,length(p.tags)-2), '><')
      end,
      array[]::varchar[]
    ) as tag_array,
    coalesce(length(title),0) as title_len,
    coalesce(length(body),0) as body_len
  from posts p
  where p.posttypeid = 1
),
answers as (
  select p.*
  from posts p
  where p.posttypeid = 2
),
-- explode tags for tag analytics
tag_exploded as (
  select
    q.id as question_id,
    q.owneruserid,
    trim(both from t) as tag
  from questions q
  cross join lateral unnest(q.tag_array) as t
  where array_length(q.tag_array,1) is not null
),
-- global tag popularity with window ranking
tag_popularity as (
  select
    tag,
    count(*) as occurrences,
    rank() over (order by count(*) desc) as global_rank,
    dense_rank() over (order by count(*) desc) as dense_global_rank
  from tag_exploded
  group by tag
),
-- per-user tag counts and pick top tag per user
user_tag_counts as (
  select
    te.owneruserid as user_id,
    te.tag,
    count(*) as tag_count,
    row_number() over (partition by te.owneruserid order by count(*) desc, te.tag) as rn
  from tag_exploded te
  group by te.owneruserid, te.tag
),
user_top_tag as (
  select utc.user_id, utc.tag, utc.tag_count
  from user_tag_counts utc
  where utc.rn = 1
),
-- badge user sets using set operators for variety
badge_gold_users as (
  select distinct userid from badges where class = 1
),
badge_silver_or_bronze as (
  select distinct userid from badges where class in (2,3)
),
-- union then except example: users who have any badge except very low rep users
users_with_some_badge as (
  (select userid from badge_gold_users)
  union
  (select userid from badge_silver_or_bronze)
  except
  (select id from users where reputation < 50)
),
-- intersect example: gold badge holders who are also high reputation
highrep_gold as (
  (select userid from badge_gold_users)
  intersect
  (select id as userid from users where reputation > 10000)
),
-- aggregated badge counts
badge_counts as (
  select
    u.userid,
    count(*) filter (where b.class = 1) as gold,
    count(*) filter (where b.class = 2) as silver,
    count(*) filter (where b.class = 3) as bronze,
    max(b.date) as last_badge_date,
    bool_or(b.tagbased = true) as has_tag_based_badge
  from badges b
  right join (select distinct userid from badges) u on u.userid = b.userid
  group by u.userid
),
-- per-user post/answer/comment/vote aggregates
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    count(distinct q.id) filter (where q.id is not null) as question_count,
    count(distinct a.id) filter (where a.id is not null) as answer_count,
    coalesce(avg(a.score) filter (where a.id is not null),0) as avg_answer_score,
    coalesce(max(p.lastactivitydate), u.lastaccessdate) as last_activity,
    sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
    count(distinct c.id) as comment_count,
    count(distinct v.id) filter (where v.votetypeid = 2) as upvotes_cast,
    count(distinct v.id) filter (where v.votetypeid = 3) as downvotes_cast
  from users u
  left join posts p on p.owneruserid = u.id
  left join questions q on q.owneruserid = u.id
  left join answers a on a.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join votes v on v.userid = u.id
  group by u.id, u.displayname, u.reputation, u.lastaccessdate
),
-- compute per-user medians of answer scores for answers to their questions (correlated via array agg)
user_median_answer_score as (
  select
    u.id as user_id,
    (
      select
        case
          when arr is null then null
          else arr[(array_length(arr,1)+1)/2]
        end
      from (
        select array_agg(a.score order by a.score) as arr
        from answers a
        where a.parentid in (select id from posts p2 where p2.owneruserid = u.id and p2.posttypeid = 1)
      ) t
    ) as median_answer_score
  from users u
),
-- combine aggregates with window ranking to produce final benchmarking rows
combined as (
  select
    ua.*,
    coalesce(bc.gold,0) as gold_badges,
    coalesce(bc.silver,0) as silver_badges,
    coalesce(bc.bronze,0) as bronze_badges,
    utt.tag as top_tag,
    tp.global_rank as top_tag_global_rank,
    um.median_answer_score,
    -- activity index: weighted, with NULL logic and defensive coercions
    (
      coalesce(ua.question_count,0) * 1.5
      + coalesce(ua.answer_count,0) * 2.0
      + coalesce(ua.avg_answer_score,0) * 3.0
      + coalesce(coalesce(bc.gold,0),0) * 10
      - coalesce(ua.downvotes_cast,0) * 0.5
    )::numeric as activity_index,
    -- window functions to rank users for benchmarking slices
    dense_rank() over (order by ua.reputation desc) as reputation_rank,
    rank() over (order by (coalesce(ua.answer_count,0) + coalesce(ua.question_count,0)) desc) as contribution_rank
  from user_activity ua
  left join badge_counts bc on bc.userid = ua.user_id
  left join user_top_tag utt on utt.user_id = ua.user_id
  left join tag_popularity tp on tp.tag = utt.tag
  left join user_median_answer_score um on um.user_id = ua.user_id
),
-- pick a sample of interesting posts per user using correlated subqueries and lateral (most recent favorite, highest-scored answer)
user_sample_posts as (
  select
    u.id as user_id,
    -- most recent post title snippet (question) by this user
    (select p.title from posts p where p.owneruserid = u.id and p.posttypeid = 1 order by p.creationdate desc limit 1) as recent_question_title,
    -- highest scored answer by the user
    (select a.id from posts a where a.owneruserid = u.id and a.posttypeid = 2 order by a.score desc nulls last, a.creationdate desc limit 1) as top_answer_id,
    -- an example of correlated subquery returning boolean: has accepted answers among their answers
    exists (
      select 1 from posts q join posts a on a.parentid = q.id
      where a.owneruserid = u.id and q.acceptedanswerid = a.id
      limit 1
    ) as has_accepted_answer
  from users u
)
select
  c.user_id,
  c.displayname,
  c.reputation,
  c.reputation_rank,
  c.contribution_rank,
  c.question_count,
  c.answer_count,
  c.avg_answer_score,
  c.median_answer_score,
  c.top_tag,
  c.top_tag_global_rank,
  c.gold_badges,
  c.silver_badges,
  c.bronze_badges,
  c.activity_index,
  c.last_activity,
  usp.recent_question_title,
  usp.top_answer_id,
  usp.has_accepted_answer,
  -- a string expression combining tag, name and medians with null-safe concatenation
  coalesce(c.top_tag,'<no-tag>') || ' :: ' || coalesce(c.displayname,'[anon]') || ' :: median=' || coalesce(cast(c.median_answer_score as varchar),'NULL') as short_summary,
  -- include boolean membership checks from set-operator CTEs
  (c.user_id in (select userid from users_with_some_badge)) as has_some_badge,
  (c.user_id in (select userid from highrep_gold)) as is_highrep_gold,
  -- additional window function demonstrating partitioning: within top tag group, rank by activity
  row_number() over (partition by coalesce(c.top_tag,'<no-tag>') order by c.activity_index desc) as rank_within_top_tag
from combined c
left join user_sample_posts usp on usp.user_id = c.user_id
where
  -- complex predicate mixing NULL logic, comparisons and subqueries: target active or notable users
  (
    (c.activity_index > 50 and c.reputation > 500)
    or c.gold_badges > 0
    or c.user_id in (select userid from users_with_some_badge)
  )
  and not (c.displayname is null and c.reputation < 10)
order by c.activity_index desc, c.reputation desc
limit 500;