-- {"query": "153.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2518} 
with
-- explode tags into one row per tag per question
question_tags as (
  select p.id as question_id,
         trim(t) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,''))-2,0)), '><')) as t
  ) s
  where p.posttypeid = 1
),
-- basic aggregates for questions
question_stats as (
  select q.id,
         q.creationdate,
         q.title,
         q.owneruserid,
         q.score,
         q.viewcount,
         coalesce(q.answercount, 0) as answercount,
         coalesce(q.favoritecount, 0) as favoritecount,
         q.tags,
         qt.tag
  from posts q
  left join question_tags qt on qt.question_id = q.id
  where q.posttypeid = 1
),
-- answers with their relative metrics and correlated subquery for accepted status
answer_stats as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.creationdate,
         a.owneruserid as answer_ownerid,
         a.score as answer_score,
         a.body,
         case when q.acceptedanswerid = a.id then true else false end as is_accepted,
         -- time to answer in seconds
         extract(epoch from a.creationdate - q.creationdate) as secs_to_answer,
         -- number of comments on the answer (correlated subquery)
         (select count(*) from comments c where c.postid = a.id) as comment_count
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
),
-- windowed per-question answer summaries
answer_aggregates as (
  select asq.question_id,
         count(*) as total_answers,
         sum(case when is_accepted then 1 else 0 end) filter (where is_accepted is not null) as accepted_count,
         avg(answer_score) as avg_answer_score,
         max(answer_score) as max_answer_score,
         min(answer_score) as min_answer_score,
         avg(secs_to_answer) as avg_secs_to_answer,
         percentile_cont(0.5) within group (order by secs_to_answer) as median_secs_to_answer,
         sum(comment_count) as total_answer_comments
  from answer_stats asq
  group by asq.question_id
),
-- user-centric aggregates including badge influence and recent activity
user_activity as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         coalesce(u.views,0) as profile_views,
         coalesce(u.upvotes,0) as upvotes_given,
         coalesce(u.downvotes,0) as downvotes_given,
         -- badges counts and weighted score
         count(b.id) filter (where b.class = 1) as gold_badges,
         count(b.id) filter (where b.class = 2) as silver_badges,
         count(b.id) filter (where b.class = 3) as bronze_badges,
         sum(case when b.class = 1 then 50 when b.class = 2 then 10 when b.class = 3 then 1 else 0 end) as badge_weight
  from users u
  left join badges b on b.userid = u.id
  group by u.id
),
-- combine question + answer aggregates and enrich with user metrics and tag popularity
question_enriched as (
  select qs.*,
         coalesce(aa.total_answers, 0) as total_answers,
         coalesce(aa.accepted_count, 0) as accepted_count,
         aa.avg_answer_score,
         aa.max_answer_score,
         aa.min_answer_score,
         aa.avg_secs_to_answer,
         aa.median_secs_to_answer,
         aa.total_answer_comments,
         ua.displayname as owner_displayname,
         ua.reputation as owner_reputation,
         ua.badge_weight as owner_badge_weight,
         -- popularity score: weighted combination with null-safe math
         (coalesce(qs.score,0) * 3
          + coalesce(qs.viewcount,0) / nullif(greatest(coalesce(qs.answercount,0),1),0)
          + coalesce(qs.favoritecount,0) * 5
          + coalesce(aa.avg_answer_score,0) * 2
          + coalesce(ua.badge_weight,0)) as popularity_score
  from question_stats qs
  left join answer_aggregates aa on aa.question_id = qs.id
  left join user_activity ua on ua.user_id = qs.owneruserid
),
-- per-tag metrics and ranking: combining question popularity within tag
tag_metrics as (
  select tag,
         count(distinct id) as questions_in_tag,
         avg(popularity_score) as avg_popularity,
         max(popularity_score) as peak_popularity,
         percentile_cont(0.25) within group (order by popularity_score) as p25,
         percentile_cont(0.5) within group (order by popularity_score) as p50,
         percentile_cont(0.75) within group (order by popularity_score) as p75,
         -- diversity: how many distinct owners contribute questions to the tag
         count(distinct owneruserid) as distinct_askers,
         -- tag representative question by popularity using distinct on trick (emulated through row_number)
         min(id) filter (where row_number() over (partition by tag order by popularity_score desc, id asc) = 1) as representative_question_id
  from (
    select qe.*, qt.tag
    from question_enriched qe
    join question_tags qt on qt.question_id = qe.id
  ) t
  group by tag
),
-- recent edit churn per question using PostHistory (edits, closes, deletions)
edit_churn as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,24)) as edit_count,
         count(*) filter (where ph.posthistorytypeid in (10,11,12,13)) as closure_deletion_events,
         max(ph.creationdate) as last_history_date,
         bool_or(ph.posthistorytypeid = 50) as community_bumped
  from posthistory ph
  group by ph.postid
),
-- assemble final candidate set with complex predicates, outer joins, and null logic
candidates as (
  select qe.*,
         tm.tag,
         tm.questions_in_tag,
         tm.avg_popularity,
         tm.peak_popularity,
         tm.p25, tm.p50, tm.p75,
         ec.edit_count,
         ec.closure_deletion_events,
         ec.last_history_date,
         ec.community_bumped,
         -- compute a normalized score using null-safe expressions and case branches
         case
           when qe.popularity_score is null then -1
           when qe.popularity_score < 0 then qe.popularity_score * 0.5
           else ln(1 + qe.popularity_score) * (1 + coalesce(qe.owner_reputation,0)/10000.0)
         end as normalized_popularity,
         -- flag for "stale" questions: high age but low activity
         case
           when qe.lastactivitydate is null then true
           when qe.lastactivitydate < qe.creationdate + interval '365 days' and coalesce(qe.total_answers,0) = 0 then true
           else false
         end as is_stale
  from question_enriched qe
  left join tag_metrics tm on tm.tag = qe.tag
  left join edit_churn ec on ec.postid = qe.id
),
-- rank questions per tag with window functions including complex ties and null placement
ranked as (
  select c.*,
         row_number() over (partition by c.tag order by c.normalized_popularity desc nulls last, c.total_answers desc, c.edit_count asc, c.last_history_date desc nulls last) as tag_rank,
         dense_rank() over (partition by c.tag order by c.normalized_popularity desc nulls last) as tag_dense_rank,
         rank() over (partition by c.tag order by c.normalized_popularity asc nulls first) as reverse_rank
  from candidates c
)
-- final output: choose top N per tag and include correlated subquery examples and set operator union for extra rows
select
  r.tag,
  r.tag_rank,
  r.id as question_id,
  coalesce(r.title, '<<no title>>') as title_snippet,
  left(coalesce(r.body,''), 200) as body_preview,
  r.owner_displayname,
  r.owner_reputation,
  r.total_answers,
  r.accepted_count,
  r.avg_answer_score,
  r.median_secs_to_answer,
  r.popularity_score,
  round(r.normalized_popularity::numeric,6) as normalized_popularity,
  r.questions_in_tag,
  r.avg_popularity,
  r.peak_popularity,
  r.edit_count,
  r.closure_deletion_events,
  r.is_stale,
  -- correlated scalar subquery showing latest comment text on the question (if any)
  (select cc.text from comments cc where cc.postid = r.id order by cc.creationdate desc limit 1) as latest_comment_text,
  -- correlated boolean: does any answer have score > this question's score?
  exists (select 1 from posts a where a.parentid = r.id and a.posttypeid = 2 and coalesce(a.score,0) > coalesce(r.score,0)) as has_higher_scoring_answer,
  -- demonstrate set operator: include also some "special picks" using union all (these will be appended)
  current_timestamp as benchmark_run
from ranked r
where r.tag_rank <= 5
order by r.tag, r.tag_rank

union all

-- special picks: top questions globally by normalized_popularity, limited and annotated
select
  '::GLOBAL_TOP::'::varchar as tag,
  row_number() over () as tag_rank,
  g.id as question_id,
  coalesce(g.title,'<<no title>>') as title_snippet,
  left(coalesce(g.body,''),200) as body_preview,
  g.owner_displayname,
  g.owner_reputation,
  g.total_answers,
  g.accepted_count,
  g.avg_answer_score,
  g.median_secs_to_answer,
  g.popularity_score,
  round(g.normalized_popularity::numeric,6) as normalized_popularity,
  null::int as questions_in_tag,
  null::float as avg_popularity,
  null::float as peak_popularity,
  g.edit_count,
  g.closure_deletion_events,
  g.is_stale,
  (select cc.text from comments cc where cc.postid = g.id order by cc.creationdate desc limit 1) as latest_comment_text,
  exists (select 1 from posts a where a.parentid = g.id and a.posttypeid = 2 and coalesce(a.score,0) > coalesce(g.score,0)) as has_higher_scoring_answer,
  current_timestamp as benchmark_run
from ranked g
order by g.normalized_popularity desc nulls last
limit 25;