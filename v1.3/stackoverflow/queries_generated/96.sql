-- {"query": "96.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2615} 
with
-- recent active questions with computed tag arrays and normalized score
recent_qs as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    coalesce(p.score,0) as score,
    coalesce(p.viewcount,0) as views,
    coalesce(p.answercount,0) as answers,
    coalesce(p.favoritecount,0) as favorites,
    -- split tags like '<sql><performance>' into array elements
    case when p.tags is null then array[]::text[] else string_to_array(substring(p.tags,2,length(p.tags)-2), '><') end as tag_array,
    -- normalized length measures & heuristics
    length(coalesce(p.body,'')) as body_len,
    greatest(0, extract(epoch from (now() - p.creationdate))::int) as age_seconds
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '180 days'
),
-- aggregate votes for posts, pivoting common vote types
vote_aggs as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_votes,
    sum(case when v.votetypeid = 1 then 1 else 0 end) as accepted_flags
  from votes v
  group by v.postid
),
-- badge density per owner in last year
owner_badges as (
  select
    b.userid,
    count(*) filter (where b.date >= now() - interval '365 days') as badges_last_year,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count
  from badges b
  group by b.userid
),
-- heuristic for engagement score using window functions and LAG/LEAD of activity on answers
answer_activity as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_owner,
    a.creationdate as answer_created,
    a.score as answer_score,
    row_number() over(partition by a.parentid order by a.creationdate asc) as answer_ord,
    lag(a.creationdate) over(partition by a.parentid order by a.creationdate asc) as prev_ans_ts,
    lead(a.creationdate) over(partition by a.parentid order by a.creationdate asc) as next_ans_ts
  from posts a
  where a.posttypeid = 2
),
-- compute inter-answer gaps and per-question summary using correlated subqueries
qa_summary as (
  select
    q.id as question_id,
    q.title,
    q.owneruserid,
    q.creationdate as q_created,
    q.score as q_score,
    q.viewcount as q_views,
    coalesce(v.upvotes,0) as total_upvotes,
    coalesce(v.downvotes,0) as total_downvotes,
    coalesce(v.favorites_votes,0) as total_favorites_votes,
    coalesce(ob.badges_last_year,0) as owner_badges_last_year,
    qa.answers,
    qa.body_len,
    qa.age_seconds,
    -- count of distinct answerers (excluding deleted owner -1)
    (select count(distinct a.owneruserid) from posts a where a.posttypeid=2 and a.parentid=q.id and a.owneruserid is not null and a.owneruserid <> -1) as distinct_answerers,
    -- time-to-first-answer (correlated)
    (select min(a.creationdate) from posts a where a.posttypeid=2 and a.parentid=q.id) as first_answer_ts,
    -- median answer score per question (approx via percentile_cont)
    (select percentile_cont(0.5) within group (order by coalesce(a.score,0)) from posts a where a.posttypeid=2 and a.parentid=q.id) as median_answer_score,
    -- whether question has accepted answer
    case when q.acceptedanswerid is not null then true else false end as has_accepted,
    -- composite tag-driven weight: sum of tag popularity (Count from Tags) for each tag on question
    (select coalesce(sum(t.count),0)
     from tags t
     where t.tagname = any (case when qa.tag_array is null then array[]::text[] else qa.tag_array end)
    ) as tag_popularity_sum,
    -- text heuristics: number of code fences (```), links (<a href=), and number of images
    (length(coalesce(q.body,'')) - length(replace(coalesce(q.body,''),'```',''))) / nullif(length('```'),0) as code_fence_count,
    (length(coalesce(q.body,'')) - length(replace(lower(coalesce(q.body,'')),'<a href',''))) / nullif(length('<a href'),0) as html_link_count,
    (length(coalesce(q.body,'')) - length(replace(lower(coalesce(q.body,'')),'<img',''))) / nullif(length('<img'),0) as image_count
  from recent_qs qa
  join posts q on q.id = qa.id
  left join vote_aggs v on v.postid = q.id
  left join owner_badges ob on ob.userid = q.owneruserid
),
-- heavy join to answers and authors with conditional outer joins and NULL handling
answers_and_authors as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_owner,
    u.reputation as answer_owner_reputation,
    u.creationdate as answer_owner_created,
    a.creationdate as answer_created,
    a.score as answer_score,
    coalesce(v.upvotes,0) as answer_upvotes,
    coalesce(v.downvotes,0) as answer_downvotes,
    -- quality heuristics for answer: score per day, reputation-adjusted score
    (coalesce(a.score,0) / nullif(greatest(1, extract(epoch from (now() - a.creationdate))::int / 86400),1)) as score_per_day,
    (coalesce(a.score,0) * greatest(1, coalesce(u.reputation,1))::numeric / 1000.0) as rep_adjusted_score,
    -- detect if answer body contains long code block or lots of links
    (length(coalesce(a.body,'')) - length(replace(coalesce(a.body,''),'```',''))) / nullif(length('```'),0) as ans_code_blocks
  from posts a
  left join users u on u.id = a.owneruserid
  left join vote_aggs v on v.postid = a.id
  where a.posttypeid = 2
),
-- flagged anomalous relations: questions linked as duplicates or linked posts within 30 days
link_checks as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    pl.creationdate,
    case when pl.linktypeid = 3 then 'duplicate' else 'linked' end as link_kind,
    abs(extract(epoch from (p.creationdate - r.creationdate))) as inter_post_seconds
  from postlinks pl
  join posts p on p.id = pl.postid
  join posts r on r.id = pl.relatedpostid
  where pl.creationdate >= now() - interval '365 days'
),
-- final ranking combining everything with window functions, set operations and correlated scoring
ranked_questions as (
  select
    qs.*,
    -- derive a composite engagement metric using many inputs and null-safe math
    (
      -- base: normalized score & views
      (coalesce(qs.q_score,0) * 2.5)
      + log(1 + greatest(0, qs.q_views)) * 0.7
      -- upvote/downvote ratio influence (smoothed)
      + (coalesce(qs.total_upvotes,0) - coalesce(qs.total_downvotes,0)) * 1.5
      -- tag popularity bonus (diminishing returns)
      + ln(1 + greatest(0, qs.tag_popularity_sum)) * 1.2
      -- answers & answer quality: more distinct answerers and higher median answer score increases engagement
      + greatest(0, qs.distinct_answerers) * 3.0
      + coalesce(qs.median_answer_score,0) * 2.0
      -- owner reputation via badges
      + coalesce(qs.owner_badges_last_year,0) * 1.8
      -- penalize old unanswered questions
      - case when qs.has_accepted = false and qs.answers = 0 then ln(1 + qs.age_seconds/86400.0) * 2 else 0 end
      -- small bonus for images and code presence (useful posts)
      + coalesce(qs.code_fence_count,0) * 1.1 + coalesce(qs.image_count,0) * 0.8
    ) as engagement_score,
    -- derive anomaly flag if linked as duplicate within 30 days or heavy downvotes
    exists (
      select 1 from link_checks lc where lc.postid = qs.question_id and lc.link_kind = 'duplicate' and lc.inter_post_seconds < 2592000
    ) as recently_duplicated,
    case when coalesce(qs.total_downvotes,0) > greatest(5, coalesce(qs.total_upvotes,0) / 4) then true else false end as controversial
  from qa_summary qs
),
-- pick top N by engagement and then expand with set operators to include some random low-engagement ones
top_and_sampling as (
  -- top 50 by engagement
  select * from ranked_questions
  order by engagement_score desc
  limit 50

  union

  -- plus a random sample of 25 low engagement questions (engagement_score in bottom 10%)
  select * from (
    select rq.*, ntile(100) over (order by rq.engagement_score) as pctile from ranked_questions rq
  ) low where pctile <= 10
  order by random()
  limit 25
)
select
  tas.question_id,
  tas.title,
  tas.q_created,
  tas.q_score,
  tas.q_views,
  tas.answers,
  tas.distinct_answerers,
  tas.has_accepted,
  tas.total_upvotes,
  tas.total_downvotes,
  tas.total_favorites_votes,
  tas.median_answer_score,
  tas.tag_popularity_sum,
  tas.owner_badges_last_year,
  tas.code_fence_count,
  tas.html_link_count,
  tas.image_count,
  tas.engagement_score,
  tas.recently_duplicated,
  tas.controversial,
  -- enrich with correlated aggregates from answers_and_authors: top answer per question by rep_adjusted_score
  (select aa.answer_id from answers_and_authors aa where aa.question_id = tas.question_id order by aa.rep_adjusted_score desc nulls last limit 1) as top_answer_id,
  (select aa.answer_owner from answers_and_authors aa where aa.question_id = tas.question_id order by aa.rep_adjusted_score desc nulls last limit 1) as top_answer_owner,
  (select aa.rep_adjusted_score from answers_and_authors aa where aa.question_id = tas.question_id order by aa.rep_adjusted_score desc nulls last limit 1) as top_answer_rep_adjusted_score,
  -- include counts of comments on question and on its top answer (correlated with null handling)
  (select count(*) from comments c where c.postid = tas.question_id) as question_comment_count,
  (select count(*) from comments c where c.postid = (select aa.answer_id from answers_and_authors aa where aa.question_id = tas.question_id order by aa.rep_adjusted_score desc nulls last limit 1)) as top_answer_comment_count
from top_and_sampling tas
order by tas.engagement_score desc, tas.q_created desc;