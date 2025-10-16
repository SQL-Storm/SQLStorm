-- {"query": "7015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2130} 
with
-- recent active questions with parsed tag array and tag count
RecentQuestions as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    coalesce(p.score,0) as score,
    coalesce(p.viewcount,0) as views,
    p.answercount,
    p.tags,
    case when p.tags is null then '{}'::text[] else string_to_array(substring(p.tags,2,length(p.tags)-2), '><') end as tag_array,
    cardinality(case when p.tags is null then '{}'::text[] else string_to_array(substring(p.tags,2,length(p.tags)-2), '><') end) as tag_count
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '365 days'
    and (p.score is not null and p.score >= -5)
),

-- per-question aggregated metadata: top answers, distinct commenters, distinct voters breakdown
QuestionStats as (
  select
    q.id as question_id,
    q.title,
    q.creationdate,
    q.owneruserid,
    q.score,
    q.views,
    q.answercount,
    q.tag_array,
    q.tag_count,
    -- top 3 answers by combined metric (score * log(views+1) + recentness factor)
    (select json_agg(a_row order by a_row.rank) from (
       select a.id, a.creationdate, a.score, a.owneruserid,
         round((coalesce(a.score,0) * ln(coalesce(a.viewcount,0)+1)::numeric) + greatest(0, extract(epoch from (now()-a.creationdate))/86400)::numeric * -0.01,4) as weight,
         row_number() over (order by ((coalesce(a.score,0) * ln(coalesce(a.viewcount,0)+1)) + greatest(0, extract(epoch from (now()-a.creationdate))/86400) * -0.01) desc) as rank
       from posts a
       where a.parentid = q.id and a.posttypeid = 2
       limit 3
    ) a_row) as top_answers,
    -- number of unique users who commented on the question in last year
    (select count(distinct c.userid) from comments c where c.postid = q.id and c.creationdate >= now() - interval '365 days') as commenters_last_year,
    -- votes breakdown for the question (upvotes, downvotes, accepts)
    (select json_build_object(
       'upvotes', coalesce(sum(case when v.votetypeid = 2 then 1 else 0 end),0),
       'downvotes', coalesce(sum(case when v.votetypeid = 3 then 1 else 0 end),0),
       'accepts', coalesce(sum(case when v.votetypeid = 1 then 1 else 0 end),0),
       'favorites', coalesce(sum(case when v.votetypeid = 5 then 1 else 0 end),0)
     )
     from votes v where v.postid = q.id
    ) as vote_breakdown,
    -- last edit history summary (most recent history type per post)
    (select json_build_object(
       'last_history_id', ph.id,
       'last_history_type', pht.name,
       'last_history_date', ph.creationdate,
       'editor_userid', ph.userid,
       'comment', left(ph.comment::text,200)
     )
     from posthistory ph
     left join posthistorytypes pht on pht.id = ph.posthistorytypeid
     where ph.postid = q.id
     order by ph.creationdate desc limit 1
    ) as last_history
  from RecentQuestions q
),

-- tag popularity in the sample set and best-performing tag contributors
TagExplode as (
  select
    qs.question_id,
    unnest(qs.tag_array) as tag
  from QuestionStats qs
),

TagAggregates as (
  select
    t.tag,
    count(*) as questions_with_tag,
    sum(qs.views) as total_views,
    avg(qs.score) as avg_score,
    max(qs.answercount) as max_answers,
    -- top answerer for this tag by sum of scores on answers in the last year
    (select u.displayname from users u
     join posts a on a.owneruserid = u.id
     where a.posttypeid = 2
       and exists (select 1 from posts pq where pq.id = a.parentid and pq.posttypeid=1 and pq.tags like ('%<'||t.tag||'>%'))
       and a.creationdate >= now() - interval '365 days'
     group by u.id,u.displayname
     order by sum(coalesce(a.score,0)) desc nulls last
     limit 1
    ) as top_answerer_name,
    -- median answer score per tag using windowed percent_rank
    (select percentile_cont(0.5) within group (order by coalesce(a.score,0)) from posts a
     where a.posttypeid = 2
       and exists (select 1 from posts pq where pq.id = a.parentid and pq.tags like ('%<'||t.tag||'>%'))
    )::numeric(10,4) as median_answer_score
  from TagExplode t
  join QuestionStats qs on qs.question_id = t.question_id
  group by t.tag
  having count(*) >= 3
  order by questions_with_tag desc
  limit 25
),

-- identify suspicious or high-variance answerers: users with both high and low scoring answers
AnswererVariance as (
  select
    a.owneruserid as userid,
    u.displayname,
    count(*) as total_answers,
    avg(coalesce(a.score,0)) as avg_score,
    stddev_pop(coalesce(a.score,0)) as score_stddev,
    sum(case when a.score >= 10 then 1 else 0 end) as high_score_count,
    sum(case when a.score <= 0 then 1 else 0 end) as nonpositive_count,
    -- fraction of answers accepted
    sum(case when exists (select 1 from posts q where q.id = a.parentid and q.acceptedanswerid = a.id) then 1 else 0 end)::float / nullif(count(*),0) as accept_rate
  from posts a
  left join users u on u.id = a.owneruserid
  where a.posttypeid = 2
    and a.creationdate >= now() - interval '365 days'
  group by a.owneruserid, u.displayname
  having count(*) >= 5
),

-- combine tag aggregates and top answerers into a ranking using set operators
TagAndAnswererScore as (
  select
    ta.tag,
    ta.questions_with_tag,
    ta.total_views,
    ta.avg_score,
    ta.max_answers,
    ta.top_answerer_name,
    ta.median_answer_score,
    coalesce(av.avg_score,0) as top_answerer_avg_score,
    coalesce(av.score_stddev,0) as top_answerer_stddev,
    -- composite score: popularity * quality / (1 + volatility)
    round((ta.questions_with_tag::numeric * greatest(1, ta.avg_score + 5) * greatest(0.1, ta.median_answer_score + 3)) / (1 + coalesce(av.score_stddev,0)),4) as composite_score
  from TagAggregates ta
  left join answerervariance av on av.displayname = ta.top_answerer_name
)

-- final selection combining queries, window functions and correlated lookups
select
  row_number() over (order by tas.composite_score desc) as ranking,
  tas.tag,
  tas.questions_with_tag,
  tas.total_views,
  tas.avg_score,
  tas.median_answer_score,
  tas.top_answerer_name,
  tas.top_answerer_avg_score,
  tas.top_answerer_stddev,
  tas.composite_score,
  -- correlated subquery: sample high-impact question for the tag which has unanswered but high view count
  (select json_build_object(
     'id', q.id,
     'title', left(q.title,120),
     'score', q.score,
     'views', q.views,
     'answercount', q.answercount,
     'age_days', round(extract(epoch from (now()-q.creationdate))/86400)::int
   )
   from posts q
   where q.posttypeid = 1
     and q.tags like ('%<'||tas.tag||'>%')
   order by (case when q.answercount = 0 then 1000000 else q.answercount end), q.views desc, q.score desc
   limit 1
  ) as sample_high_impact_question,
  -- correlated boolean: whether this tag has at least one question closed in last year
  exists (
    select 1 from posthistory ph
    where ph.postid in (select id from posts p where p.tags like ('%<'||tas.tag||'>%'))
      and ph.posthistorytypeid = 10
      and ph.creationdate >= now() - interval '365 days'
    limit 1
  ) as has_close_in_last_year,
  -- aggregate of recent badge awards to contributors in tag (gold/silver/bronze)
  (select json_agg(bd) from (
     select ub.name as badge_name, ub.class as badge_class, count(*) as awarded_count
     from badges ub
     join users bx on bx.id = ub.userid
     where ub.date >= now() - interval '365 days'
       and exists (select 1 from posts pq where pq.owneruserid = ub.userid and pq.tags like ('%<'||tas.tag||'>%'))
     group by ub.name, ub.class
     order by awarded_count desc
     limit 5
  ) bd) as recent_badges
from TagAndAnswererScore tas
order by tas.composite_score desc, tas.questions_with_tag desc
limit 20;