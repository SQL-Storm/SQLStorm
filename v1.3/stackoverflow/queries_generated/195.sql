-- {"query": "195.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2248} 
with
-- recent activity per user: last post, last comment, last vote
recent_activity as (
  select u.id as user_id,
         u.displayname,
         greatest(
           coalesce(max(p.lastactivitydate), '1970-01-01'::timestamp),
           coalesce(max(c.creationdate), '1970-01-01'::timestamp),
           coalesce(max(v.creationdate), '1970-01-01'::timestamp)
         ) as last_activity,
         max(p.id) filter (where p.lastactivitydate is not null) as last_post_id,
         max(c.id) filter (where c.creationdate is not null) as last_comment_id,
         max(v.id) filter (where v.creationdate is not null) as last_vote_id
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join votes v on v.userid = u.id
  group by u.id, u.displayname
),
-- tag explosion: question id -> individual tags (keep tag position order)
question_tags as (
  select p.id as question_id,
         trim(t) as tag,
         row_number() over (partition by p.id order by ord) as tag_pos
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''),2,length(coalesce(p.tags,''))-2),'><')) with ordinality as t(tag, ord)
  ) s
  where p.posttypeid = 1 and p.tags is not null and p.tags <> ''
),
-- per-question aggregated tag metrics
question_tag_metrics as (
  select qt.question_id,
         qt.tag,
         count(distinct a.id) filter (where a.posttypeid = 2) as answer_count,
         sum(a.score) filter (where a.posttypeid = 2) as answers_score_sum,
         max(a.score) filter (where a.posttypeid = 2) as answers_score_max,
         p.score as question_score,
         p.viewcount,
         p.creationdate
  from question_tags qt
  join posts p on p.id = qt.question_id
  left join posts a on a.parentid = p.id and a.posttypeid = 2
  group by qt.question_id, qt.tag, p.score, p.viewcount, p.creationdate
),
-- per-tag leaderboards and moving averages
tag_stats as (
  select tag,
         count(*) as questions_with_tag,
         sum(question_score) as tag_questions_score_sum,
         avg(answer_count) as avg_answers_per_question,
         percentile_cont(0.5) within group (order by answers_score_sum) as median_answer_score_sum,
         sum(case when creationdate > now() - interval '180 days' then 1 else 0 end) as recent_questions_180d
  from question_tag_metrics
  group by tag
),
-- users' question/answer productivity and quality
user_post_stats as (
  select u.id as user_id,
         count(p.id) filter (where p.posttypeid = 1) as questions_count,
         count(p.id) filter (where p.posttypeid = 2) as answers_count,
         coalesce(sum(p.score) filter (where p.posttypeid in (1,2)),0) as total_post_score,
         coalesce(avg(p.score) filter (where p.posttypeid in (1,2)),0) as avg_post_score,
         sum(case when p.posttypeid = 1 and p.viewcount > 1000 then 1 else 0 end) as popular_questions
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
-- correlate badges and tag expertise: for each user, find their top tag by recent answered questions score
user_tag_expertise as (
  select up.user_id,
         qt.tag,
         sum(coalesce(a.score,0)) as answers_score_to_tag,
         count(distinct a.id) as answers_to_tag_count,
         row_number() over (partition by up.user_id order by sum(coalesce(a.score,0)) desc, count(distinct a.id) desc) as rn
  from user_post_stats up
  join posts a on a.owneruserid = up.user_id and a.posttypeid = 2
  join posts q on q.id = a.parentid and q.posttypeid = 1
  join question_tags qt on qt.question_id = q.id
  group by up.user_id, qt.tag
),
user_top_tag as (
  select user_id, tag, answers_score_to_tag, answers_to_tag_count
  from user_tag_expertise
  where rn = 1
),
-- detect potentially anomalous votes (e.g., many votes clustered on a single post by same user)
suspicious_vote_patterns as (
  select v.userid,
         v.postid,
         count(*) as votes_by_user_on_post,
         min(v.creationdate) as first_vote,
         max(v.creationdate) as last_vote
  from votes v
  where v.userid is not null
  group by v.userid, v.postid
  having count(*) > 3
),
-- sample heavy join: combine users, recent activity, post stats, top tag, and suspicious votes existence
user_summary as (
  select u.id,
         u.displayname,
         u.reputation,
         ra.last_activity,
         ups.questions_count,
         ups.answers_count,
         ups.total_post_score,
         coalesce(utt.tag,'<none>') as top_tag,
         coalesce(utt.answers_score_to_tag,0) as top_tag_score,
         coalesce(svp.votes_by_user_on_post,0) as suspicious_votes_count,
         -- string expression with null logic
         case
           when u.websiteurl is not null and u.websiteurl <> '' then
             left(u.websiteurl, 60) || case when length(u.websiteurl) > 60 then '...' else '' end
           when u.location is not null then
             'loc:' || left(u.location,40)
           else
             'no-profile'
         end as contact_hint,
         -- derived engagement metric (window function example)
         rank() over (order by ups.total_post_score desc nulls last, ups.answers_count desc) as quality_rank
  from users u
  left join recent_activity ra on ra.user_id = u.id
  left join user_post_stats ups on ups.user_id = u.id
  left join user_top_tag utt on utt.user_id = u.id
  left join suspicious_vote_patterns svp on svp.userid = u.id
),
-- top tags overall (set operator example)
top_tags_recent as (
  select tag, count(*) as qcount
  from question_tag_metrics qtm
  where qtm.creationdate > now() - interval '365 days'
  group by tag
  order by qcount desc
  limit 50
),
top_tags_alltime as (
  select tag, count(*) as qcount
  from question_tag_metrics
  group by tag
  order by qcount desc
  limit 50
),
union_top_tags as (
  select tag, qcount from top_tags_recent
  union
  select tag, qcount from top_tags_alltime
)
-- final selection: heavy correlated subqueries and filters, outer joins, windowing, and boolean logic
select
  us.id as user_id,
  us.displayname,
  us.reputation,
  us.questions_count,
  us.answers_count,
  us.total_post_score,
  us.top_tag,
  us.top_tag_score,
  us.suspicious_votes_count,
  us.contact_hint,
  us.quality_rank,
  -- correlated subquery: best answer provided by this user (score-wise), with tie-breaker recent
  (
    select a.id
    from posts a
    where a.owneruserid = us.id and a.posttypeid = 2
    order by a.score desc nulls last, a.creationdate desc
    limit 1
  ) as best_answer_id,
  -- correlated scalar: average score on answers to top_tag within last year
  (
    select avg(a.score)::numeric(12,3)
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    join question_tags qt on qt.question_id = q.id and qt.tag = us.top_tag
    where a.owneruserid = us.id and a.posttypeid = 2 and a.creationdate > now() - interval '365 days'
  ) as avg_score_on_top_tag_last_year,
  -- boolean indicator via exists (correlated)
  exists (
    select 1 from posts p where p.owneruserid = us.id and p.posttypeid = 1 and p.viewcount > 10000
  ) as has_very_popular_question,
  -- windowed percentile of user's reputation among peers who have >0 posts
  percentile_cont(0.75) within group (order by u2.reputation) over () as global_75th_reputation,
  -- include a list of top union tags showing if user's top_tag is in them (string expression + null logic)
  (
    select string_agg(distinct ut.tag || ':' || ut.qcount::text, ', ' order by ut.qcount desc)
    from union_top_tags ut
    where ut.tag is not null
    limit 1
  ) as sample_top_tags,
  -- demonstration of NULL logic and CASE with multiple predicates
  case
    when us.reputation >= 10000 then 'elite'
    when us.reputation >= 1000 and us.answers_count >= 50 then 'prolific'
    when us.reputation >= 0 and (us.questions_count + us.answers_count) = 0 then 'lurker'
    when us.suspicious_votes_count > 0 then 'flag-suspected'
    else 'regular'
  end as user_tier
from user_summary us
left join users u2 on true -- simple cross join to allow window percentile computation to reference users table; no filtering intended
where (us.questions_count is not null and us.questions_count >= 1)
   or (us.answers_count is not null and us.answers_count >= 5)
order by us.quality_rank asc, us.total_post_score desc
limit 200;