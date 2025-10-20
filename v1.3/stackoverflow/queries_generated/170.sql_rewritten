-- {"query": "170.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2248} 
with
-- explode tags per question
question_tags as (
  select p.id as post_id, u.id as owner_id,
         lower(trim(t.tag)) as tag
  from posts p
  join users u on p.owneruserid = u.id
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2,0)), '><')) as tag
  ) t
  where p.posttypeid = 1 and coalesce(p.tags,'') <> ''
),
-- per-user tag summary
user_tag_stats as (
  select qt.owner_id,
         qt.tag,
         count(*) as tag_count,
         sum(coalesce(p.score,0)) as tag_score
  from question_tags qt
  join posts p on p.id = qt.post_id
  group by qt.owner_id, qt.tag
),
-- badges per user with recent and type breakdown
badge_agg as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         max(b.date) as last_badge_date,
         count(*) as total_badges
  from badges b
  group by b.userid
),
-- per-user post aggregates: questions, answers, avg score, median score approx via percentile_cont
user_post_stats as (
  select u.id as user_id,
         count(p.id) filter (where p.posttypeid = 1) as question_count,
         count(p.id) filter (where p.posttypeid = 2) as answer_count,
         sum(coalesce(p.viewcount,0)) as total_views,
         avg(coalesce(p.score,0)) filter (where p.posttypeid in (1,2)) as avg_post_score,
         percentile_cont(0.5) within group (order by coalesce(p.score,0)) filter (where p.posttypeid in (1,2)) as median_post_score,
         max(p.lastactivitydate) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
-- windowed ranking of each user's posts by score and activity
ranked_posts as (
  select p.*,
         row_number() over (partition by coalesce(p.owneruserid,-1) order by coalesce(p.score,0) desc, p.lastactivitydate desc) as rank_by_score,
         row_number() over (partition by coalesce(p.owneruserid,-1) order by p.lastactivitydate desc) as rank_by_activity
  from posts p
),
-- assemble per-user favorite tag (highest count, tie-break by tag_score then tag name)
favorite_tags as (
  select uts.owner_id as user_id,
         (array_agg(uts.tag order by uts.tag_count desc, uts.tag_score desc, uts.tag))[1] as favorite_tag,
         (array_agg(uts.tag_count order by uts.tag_count desc, uts.tag_score desc, uts.tag))[1] as favorite_tag_count
  from user_tag_stats uts
  group by uts.owner_id
),
-- recent activity union: recent posts and recent comments into single timeline, with subtle NULL logic
recent_activity as (
  select p.owneruserid as user_id, p.id as item_id, 'post' as item_type, p.creationdate as created_at, p.score, p.posttypeid, p.title
  from posts p
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' and p.owneruserid is not null

  union all

  select c.userid as user_id, c.id as item_id, 'comment' as item_type, c.creationdate as created_at, c.score, null::int as posttypeid, null::varchar as title
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' and c.userid is not null
),
-- last activity by user considering posts, comments, badges, votes (correlated subquery for last vote date)
last_activity as (
  select u.id as user_id,
         greatest(
           coalesce((
             select max(p.lastactivitydate) from posts p where p.owneruserid = u.id
           ), '-infinity'::timestamp),
           coalesce((
             select max(c.creationdate) from comments c where c.userid = u.id
           ), '-infinity'::timestamp),
           coalesce(ba.last_badge_date, '-infinity'::timestamp),
           coalesce((
             select max(v.creationdate) from votes v where v.userid = u.id
           ), '-infinity'::timestamp)
         ) as last_activity_date
  from users u
  left join badge_agg ba on ba.userid = u.id
),
-- union set operator example: highly active users from two different heuristics
high_activity_candidates as (
  select user_id from user_post_stats ups where ups.question_count + ups.answer_count >= 50
  union
  select userid as user_id from badges where date >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' group by userid having count(*) >= 10
  except
  select id from users where reputation < 100
),
-- final selection: combine everything with various joins, correlated subqueries for accepted answer ratio and duplicate link count
final_users as (
  select u.id,
         u.displayname,
         u.reputation,
         ups.question_count,
         ups.answer_count,
         ups.avg_post_score,
         ups.median_post_score,
         coalesce(ba.gold_badges,0) as gold_badges,
         coalesce(ba.silver_badges,0) as silver_badges,
         coalesce(ba.bronze_badges,0) as bronze_badges,
         ft.favorite_tag,
         ft.favorite_tag_count,
         la.last_activity_date,
         -- accepted answer ratio: answers that are accepted / total answers (handle divide by zero)
         (select count(*) from posts p where p.posttypeid = 2 and p.owneruserid = u.id and exists (select 1 from posts q where q.id = p.id and q.id in (select acceptedanswerid from posts where acceptedanswerid is not null))) as accepted_as_answer_count,
         (select count(*) from posts p where p.posttypeid = 2 and p.owneruserid = u.id) as total_answers,
         -- duplicate link count (posts that are marked duplicate linking to others)
         (select count(*) from postlinks pl join linktypes lt on lt.id = pl.linktypeid where pl.postid in (select id from posts where owneruserid = u.id) and lt.name ilike '%duplicate%') as duplicate_links_out,
         -- whether user has recently been active in last_activity CTE (boolean)
         (case when la.last_activity_date >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then true else false end) as active_30d
  from users u
  left join user_post_stats ups on ups.user_id = u.id
  left join badge_agg ba on ba.userid = u.id
  left join favorite_tags ft on ft.user_id = u.id
  left join last_activity la on la.user_id = u.id
  where u.id in (select user_id from high_activity_candidates)
),
-- assemble example representative posts per user (top scored and most recent) via joins to ranked_posts
representative_posts as (
  select fu.id as user_id,
         rp_top.id as top_post_id, rp_top.title as top_post_title, rp_top.score as top_post_score, rp_top.posttypeid as top_post_type,
         rp_recent.id as recent_post_id, rp_recent.title as recent_post_title, rp_recent.creationdate as recent_post_date
  from final_users fu
  left join ranked_posts rp_top on rp_top.owneruserid = fu.id and rp_top.rank_by_score = 1
  left join ranked_posts rp_recent on rp_recent.owneruserid = fu.id and rp_recent.rank_by_activity = 1
)
-- final output: elaborate selection, calculations, windowed ranking over final users
select fu.*,
       rp.top_post_id, rp.top_post_title, rp.top_post_score, rp.top_post_type,
       rp.recent_post_id, rp.recent_post_title, rp.recent_post_date,
       -- compute acceptance ratio safely and friendly string with NULL logic and formatting
       (case when coalesce(fu.total_answers,0) = 0 then null
             else round(100.0 * coalesce(fu.accepted_as_answer_count,0) / fu.total_answers,2)
        end) as accepted_answer_percent,
       -- z-score of reputation among the selected final users (window function)
       (fu.reputation - avg(fu.reputation) over ()) / nullif(stddev_samp(fu.reputation) over (),0) as reputation_zscore,
       -- synthetic complexity score combining several factors with null-handling
       round(
         coalesce(fu.question_count,0) * 0.6
         + coalesce(fu.answer_count,0) * 0.8
         + coalesce(fu.avg_post_score,0) * 1.5
         + (coalesce(fu.gold_badges,0) * 5 + coalesce(fu.silver_badges,0) * 2 + coalesce(fu.bronze_badges,0) * 0.5)
         - (case when fu.active_30d then 0 else 3 end)
       ,2) as complexity_score
from final_users fu
left join representative_posts rp on rp.user_id = fu.id
order by complexity_score desc, fu.reputation desc
limit 250;