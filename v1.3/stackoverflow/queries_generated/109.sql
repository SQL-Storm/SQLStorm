-- {"query": "109.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2326} 
with
-- base questions and answers
q as (
  select p.*
  from posts p
  where p.posttypeid = 1
),
a as (
  select p.*
  from posts p
  where p.posttypeid = 2
),
-- explode tags into one row per tag per question
q_tags as (
  select
    q.id as question_id,
    trim(both '<>' from t) as tag
  from q
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(q.tags,''),2, greatest(length(coalesce(q.tags,'')) - 2,0)) , '><')) as t
  ) s
  where coalesce(q.tags,'') <> ''
),
-- aggregate per-question metrics including time-to-accepted-answer and answer distributions
q_metrics as (
  select
    q.id,
    q.owneruserid,
    q.creationdate as q_created,
    q.acceptedanswerid,
    q.score as q_score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    -- time to accepted answer in seconds (null if no accepted)
    case
      when q.acceptedanswerid is not null then
        extract(epoch from ( (select a2.creationdate from posts a2 where a2.id = q.acceptedanswerid) - q.creationdate ))
      else null
    end as seconds_to_accepted,
    -- median answer score for this question (using windowed aggregation on answers)
    (select percentile_cont(0.5) within group (order by coalesce(ans.score,0))
     from posts ans
     where ans.parentid = q.id and ans.posttypeid = 2) as median_answer_score,
    -- count of answers with score >= 0 and <0
    sum(case when a.score is null then 0 when a.score >= 0 then 1 else 0 end) over (partition by q.id) as answers_nonnegative,
    sum(case when a.score is null then 0 when a.score < 0 then 1 else 0 end) over (partition by q.id) as answers_negative
  from q
  left join a on a.parentid = q.id
  group by q.id, q.owneruserid, q.creationdate, q.acceptedanswerid, q.score, q.viewcount, q.answercount, q.favoritecount
),
-- user-level aggregates: answers authored, accepted ratios, avg score, recency, badge counts
user_answers as (
  select
    u.id as user_id,
    u.displayname,
    u.creationdate as user_created,
    count(distinct ans.id) filter (where ans.posttypeid = 2) as answers_count,
    count(distinct ans.id) filter (where ans.id in (select p.acceptedanswerid from posts p where p.acceptedanswerid is not null)) as answers_accepted_count,
    avg(coalesce(ans.score,0)) filter (where ans.posttypeid = 2) as avg_answer_score,
    -- average time to acceptance for user's accepted answers (only when answer is accepted)
    avg( extract(epoch from ( (select q.creationdate from posts q where q.id = ans.parentid) - ans.creationdate ) ) * -1 ) filter (where exists (select 1 from posts q2 where q2.acceptedanswerid = ans.id)) as avg_time_before_accepted_seconds,
    max(ans.creationdate) as last_answer_date
  from users u
  left join posts ans on ans.owneruserid = u.id and ans.posttypeid = 2
  group by u.id, u.displayname, u.creationdate
),
user_badges as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_based_badges
  from badges b
  group by b.userid
),
-- tag popularity and median question score per tag
tag_stats as (
  select
    t.tag,
    count(distinct q.id) as questions_with_tag,
    avg(q.score) as avg_question_score,
    percentile_cont(0.5) within group (order by q.score) as median_question_score,
    sum(coalesce(q.viewcount,0)) as total_views
  from q_tags t
  join q on q.id = t.question_id
  group by t.tag
),
-- identify hot tags by combined metric, using window ranking
tag_ranks as (
  select
    *,
    dense_rank() over (order by (coalesce(questions_with_tag,0) * 0.6 + coalesce(total_views,0) * 0.0001 + coalesce(avg_question_score,0)) desc) as hot_rank
  from tag_stats
),
-- assemble final candidate rows combining users, their answer stats, and top tags they've answered in
user_top_tags as (
  select
    ua.user_id,
    ua.displayname,
    ua.answers_count,
    ua.answers_accepted_count,
    ua.avg_answer_score,
    ua.avg_time_before_accepted_seconds,
    ub.badge_count,
    ub.gold, ub.silver, ub.bronze,
    -- top 3 tags for this user by number of answers (tie-breaker by avg answer score)
    (select string_agg(tag || ':' || cnt || ':' || round(avg_score::numeric,2), ',' order by cnt desc, avg_score desc)
     from (
       select qt.tag,
              count(*) as cnt,
              avg(coalesce(ans.score,0)) as avg_score
       from posts ans
       join q_tags qt on qt.question_id = ans.parentid
       where ans.owneruserid = ua.user_id and ans.posttypeid = 2
       group by qt.tag
       order by cnt desc, avg_score desc
       limit 3
     ) t) as top_tags_summary,
    -- whether the user has any answers that are accepted within 1 hour
    exists (
      select 1 from posts ans2
      where ans2.owneruserid = ua.user_id
        and ans2.posttypeid = 2
        and exists (
          select 1 from posts q2 where q2.acceptedanswerid = ans2.id and extract(epoch from (q2.creationdate - ans2.creationdate)) <= 3600
        )
    ) as has_fast_accepted
  from user_answers ua
  left join user_badges ub on ub.userid = ua.user_id
),
-- construct a synthetic set combining: top answerers, hot tags, and anomalous questions (low score but high views)
combined as (
  select 'top_answerers' as source, ut.* , null::text as tag, null::int as questions_with_tag, null::numeric as tag_median_score, row_number() over () as seq
  from user_top_tags ut
  where ut.answers_count >= 50
  union all
  select 'hot_tags' as source, null::int as user_id, null::varchar as displayname, null::int as answers_count, null::int as answers_accepted_count, null::numeric as avg_answer_score, null::numeric as avg_time_before_accepted_seconds, null::int as badge_count, null::int as gold, null::int as silver, null::int as bronze, null::text as top_tags_summary, null::boolean as has_fast_accepted,
         tr.tag, tr.questions_with_tag, tr.median_question_score, row_number() over () as seq
  from tag_ranks tr
  where tr.hot_rank <= 10
  union all
  select 'anomalous_questions' as source,
    null::int, null::varchar, null::int, null::int, null::numeric, null::numeric, null::int, null::int, null::int, null::int, null::text,
    null::boolean,
    substring(regexp_replace(q.title, '\s+', ' ', 'g') from 1 for 80) as tag,
    q.viewcount as questions_with_tag,
    q_metrics.median_answer_score,
    row_number() over () as seq
  from q
  join q_metrics on q_metrics.id = q.id
  where q.score <= 0 and q.viewcount > 10000
  order by source, seq
)
select
  c.source,
  c.user_id,
  c.displayname,
  c.answers_count,
  c.answers_accepted_count,
  -- acceptance ratio with null/zero safety and formatted percent string
  case
    when c.answers_count is null or c.answers_count = 0 then 'N/A'
    else concat( round(100.0 * coalesce(c.answers_accepted_count,0) / greatest(c.answers_count,1)::numeric,2), '%' )
  end as acceptance_rate,
  round(coalesce(c.avg_answer_score,0)::numeric,3) as avg_answer_score,
  case when c.avg_time_before_accepted_seconds is null then null else (c.avg_time_before_accepted_seconds/3600)::numeric end as avg_time_to_accept_hours,
  c.badge_count,
  c.gold, c.silver, c.bronze,
  coalesce(c.top_tags_summary, '') as top_tags_summary,
  c.has_fast_accepted,
  c.tag as tag_or_title_snippet,
  c.questions_with_tag,
  round(coalesce(c.tag_median_score,0)::numeric,2) as tag_median_score
from combined c
-- correlate to users table to pull reputation and recency where available
left join users u on u.id = c.user_id
where
  -- filter to interesting rows: any top answerer or hot tag or anomalous question
  (c.source = 'top_answerers' and c.answers_count is not null)
  or (c.source = 'hot_tags')
  or (c.source = 'anomalous_questions')
order by
  case when c.source = 'top_answerers' then 1 when c.source = 'hot_tags' then 2 else 3 end,
  coalesce(c.answers_count,0) desc,
  coalesce(c.questions_with_tag,0) desc
limit 200;