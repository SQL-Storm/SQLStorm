-- {"query": "7077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1544} 
with
-- recent high-impact questions with tag parsing and computed tag score
RecentQuestions as (
  select p.id,
         p.title,
         p.creationdate,
         p.owneruserid,
         p.score,
         p.viewcount,
         p.answercount,
         coalesce(p.tags, '') as tags_raw,
         -- split tags: tags are stored like '<sql><performance>' so extract individual tokens
         regexp_split_to_table(substring(coalesce(p.tags,'') from 2 for greatest(length(coalesce(p.tags,''))-2,0)), '\>\<') as tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '1 year'
    and (p.score >= 10 or p.viewcount >= 1000 or p.answercount >= 3)
),
-- compute per-question tag rarity and aggregated tag metrics
TagMetrics as (
  select q.id as question_id,
         q.title,
         q.creationdate,
         q.owneruserid,
         q.score,
         q.viewcount,
         q.answercount,
         q.tag,
         t.count as global_tag_count,
         -- a synthetic tag weight: inverse popularity times presence of tag in title
         (1.0 / nullif(t.count,0)) * (case when lower(q.title) like '%' || lower(q.tag) || '%' then 2.0 else 1.0 end) as tag_weight
  from RecentQuestions q
  left join tags t on lower(t.tagname) = lower(q.tag)
),
-- aggregate tag weights per question
QuestionTagScores as (
  select question_id,
         title,
         creationdate,
         owneruserid,
         score,
         viewcount,
         answercount,
         sum(coalesce(tag_weight,0)) as tag_score,
         count(*) filter (where global_tag_count is null) as unknown_tag_count,
         array_agg(distinct tag order by tag) as tag_list
  from TagMetrics
  group by question_id, title, creationdate, owneruserid, score, viewcount, answercount
),
-- user-level aggregates including activity windows and badge context
UserActivity as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         count(distinct p.id) filter (where p.posttypeid = 1) as questions_posted,
         count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
         count(distinct b.id) as badges_earned,
         max(b.class) as top_badge_class,
         -- rolling window: posts in last 90 days
         sum(case when p.creationdate >= now() - interval '90 days' then 1 else 0 end) as posts_90d,
         -- derived recency score (more recent last access is better)
         extract(epoch from (now() - u.lastaccessdate))/86400.0 as days_since_last_access
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate
),
-- join questions with owner activity and compute a composite HOTNESS metric with windowing and correlated subquery
QuestionEnriched as (
  select q.question_id,
         q.title,
         q.creationdate,
         q.owneruserid,
         u.displayname as owner_name,
         q.score,
         q.viewcount,
         q.answercount,
         q.tag_score,
         q.unknown_tag_count,
         q.tag_list,
         u.reputation as owner_reputation,
         u.badges_earned,
         u.posts_90d,
         -- normalized factors
         (q.score::numeric * 1.5) +
         (log(greatest(q.viewcount,1)) * 2.0) +
         (q.answercount * 3.0) +
         (coalesce(q.tag_score,0) * 50.0) +
         (log(greatest(u.reputation,1)) * 1.2) -
         (greatest(u.days_since_last_access,0) * 0.05) as hotness_base,
         -- correlated subquery: count of distinct users who commented on the question in last 30 days
         (select count(distinct c.userid) from comments c where c.postid = q.question_id and c.creationdate >= now() - interval '30 days') as recent_commenters,
         -- correlated subquery: number of distinct posts linked to this question (both directions) over last year
         (select count(*) from postlinks pl where (pl.postid = q.question_id or pl.relatedpostid = q.question_id) and pl.creationdate >= now() - interval '1 year') as recent_links
  from QuestionTagScores q
  left join UserActivity u on u.user_id = q.owneruserid
),
-- final scoring with window functions, LAG/LEAD and set operators for edge cases
FinalRanked as (
  select qe.*,
         -- augment hotness with recent social signals
         (hotness_base + coalesce(recent_commenters,0) * 5 + coalesce(recent_links,0) * 2 - (unknown_tag_count * 20)) as hotness_score,
         row_number() over (order by (hotness_base + coalesce(recent_commenters,0) * 5 + coalesce(recent_links,0) * 2 - (unknown_tag_count * 20)) desc, viewcount desc) as rn,
         rank() over (partition by owneruserid order by creationdate desc) as owner_recent_rank,
         lag(hotness_base) over (order by creationdate) as prev_hotness,
         lead(hotness_base) over (order by creationdate) as next_hotness
  from QuestionEnriched qe
),
-- union in a synthetic "canonical" set of benchmark rows: top N by different criteria using set operators
TopByVarious as (
  select * from FinalRanked where rn <= 50
  union
  select * from FinalRanked where viewcount >= (select percentile_cont(0.90) within group (order by viewcount) from FinalRanked)
  except
  select * from FinalRanked where owner_recent_rank > 5
)
select
  t.question_id,
  t.title,
  t.owneruserid,
  coalesce(t.owner_name, '(deleted)') as owner_name,
  t.creationdate,
  t.score,
  t.viewcount,
  t.answercount,
  array_to_string(t.tag_list, ',') as tags,
  round(t.tag_score::numeric,4) as tag_score,
  t.unknown_tag_count,
  t.owner_reputation,
  t.badges_earned,
  t.posts_90d,
  round(t.hotness_base::numeric,4) as hotness_base,
  t.recent_commenters,
  t.recent_links,
  round(t.hotness_score::numeric,4) as hotness_score,
  t.rn,
  t.owner_recent_rank,
  t.prev_hotness,
  t.next_hotness
from TopByVarious t
order by hotness_score desc, viewcount desc, creationdate desc
limit 200;