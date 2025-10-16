-- {"query": "136.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2620} 
with
-- explode tags from questions
question_tags as (
  select p.id as question_id,
         lower(trim(t)) as tag
  from posts p
  cross join lateral (
    select regexp_split_to_table(substring(coalesce(p.tags, ''), 2, greatest(char_length(coalesce(p.tags, ''))-2,0)), '><') as t
  ) as toks
  where p.posttypeid = 1
),
-- answers with acceptance and time-to-accept
answers as (
  select a.*,
         a.parentid as question_id,
         case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted,
         -- time from answer creation to question acceptance (null if not accepted or q.AcceptedAnswerId != this answer)
         case when q.acceptedanswerid = a.id and q.creationdate is not null and a.creationdate is not null
              then extract(epoch from (q.lastactivitydate - a.creationdate))::bigint
              else null end as seconds_to_accept
  from posts a
  left join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
),
-- per-user aggregates for answers and questions
user_post_agg as (
  select u.id as user_id,
         u.displayname,
         count(distinct q.id) filter (where q.posttypeid = 1) as question_count,
         count(distinct a.id) filter (where a.posttypeid = 2) as answer_count,
         sum(coalesce(a.score,0)) as total_answer_score,
         sum(coalesce(q.score,0)) as total_question_score,
         max(u.reputation) as reputation,
         count(distinct b.id) as badge_count,
         -- average time to acceptance for answers by this user (in seconds)
         avg(a2.seconds_to_accept) filter (where a2.seconds_to_accept is not null) as avg_seconds_to_accept
  from users u
  left join posts q on q.owneruserid = u.id and q.posttypeid = 1
  left join posts a on a.owneruserid = u.id and a.posttypeid = 2
  left join answers a2 on a2.id = a.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname
),
-- badge quality score: gold=3,silver=2,bronze=1 and tag-based multiplier
badge_score as (
  select userid,
         sum((case when class=1 then 3 when class=2 then 2 when class=3 then 1 else 0 end) *
             (case when tagbased then 1.25 else 1 end)
         ) as badge_points
  from badges
  group by userid
),
-- user tag expertise: count of answers per tag and average answer score per tag
user_tag_expertise as (
  select a.owneruserid as user_id,
         qt.tag,
         count(*) as answers_for_tag,
         avg(coalesce(a.score,0)) as avg_answer_score_for_tag,
         row_number() over (partition by a.owneruserid order by count(*) desc, avg(coalesce(a.score,0)) desc) as tag_rank
  from posts a
  join question_tags qt on qt.question_id = a.parentid
  where a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid, qt.tag
),
-- top tag per user (if any)
user_top_tag as (
  select user_id, tag as top_tag, answers_for_tag, avg_answer_score_for_tag
  from user_tag_expertise
  where tag_rank = 1
),
-- recent activity windows and moving averages per user (last 6 months vs all time)
recent_activity as (
  select u.id as user_id,
         sum(case when p.creationdate >= now() - interval '6 months' then 1 else 0 end) filter (where p.posttypeid in (1,2)) as posts_last_6m,
         sum(case when v.creationdate >= now() - interval '6 months' and v.votetypeid = 2 then 1 else 0 end) as upvotes_received_last_6m,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received_alltime
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.postid = p.id
  group by u.id
),
-- combine everything
combined as (
  select u.user_id,
         u.displayname,
         u.reputation,
         coalesce(u.answer_count,0) as answer_count,
         coalesce(u.question_count,0) as question_count,
         coalesce(u.total_answer_score,0) as total_answer_score,
         coalesce(b.badge_points,0) as badge_points,
         coalesce(ut.top_tag, '<<none>>') as top_tag,
         coalesce(ut.answers_for_tag,0) as answers_for_top_tag,
         coalesce(ut.avg_answer_score_for_tag,0) as avg_score_on_top_tag,
         coalesce(u.avg_seconds_to_accept, 1e9) as avg_seconds_to_accept,
         coalesce(r.posts_last_6m,0) as posts_last_6m,
         coalesce(r.upvotes_received_last_6m,0) as upvotes_last_6m,
         -- complex composite score using nonlinear scaling, null-safe operations and string ops
         (
           -- base: reputation scaled logarithmically, with null-safe default
           (case when u.reputation > 0 then ln(u.reputation + 10) else 0 end) * 3.0
           + sqrt(greatest(coalesce(u.answer_count,0),0)) * 5.0
           + (coalesce(u.total_answer_score,0) * 0.75)
           + coalesce(b.badge_points,0) * 2.0
           + (coalesce(ut.avg_answer_score_for_tag,0) * 4.0)
           + (1.0 / nullif(1.0 + least(coalesce(u.avg_seconds_to_accept,1e9), 1e9),0)) * 10000.0
           + coalesce(r.upvotes_last_6m,0) * 1.5
         ) as composite_score,
         -- human-friendly summary generated via string concatenation and NULL logic
         concat_ws(' | ',
           coalesce(u.displayname,'<anon>'),
           'rep='||coalesce(u.reputation::text,'0'),
           'A='||coalesce(u.answer_count::text,'0'),
           'Q='||coalesce(u.question_count::text,'0'),
           'top_tag='||coalesce(ut.top_tag,'<none>'),
           'badges='||coalesce(b.badge_points::text,'0')
         ) as quick_summary
  from user_post_agg u
  left join badge_score b on b.userid = u.user_id
  left join user_top_tag ut on ut.user_id = u.user_id
  left join recent_activity r on r.user_id = u.user_id
),
-- select candidate users who are either prolific answerers or received many upvotes recently
candidates as (
  select * from combined
  where (answer_count >= 10 or upvotes_last_6m >= 20 or badge_points >= 5)
),
-- correlated subquery example: compute each candidate's best answer by score and see if it was accepted
best_answer_lookup as (
  select c.*,
         (select a.id from posts a
          where a.owneruserid = c.user_id and a.posttypeid = 2
          order by a.score desc nulls last, a.creationdate asc
          limit 1
         ) as best_answer_id,
         (select a.score from posts a
          where a.owneruserid = c.user_id and a.posttypeid = 2
          order by a.score desc nulls last, a.creationdate asc
          limit 1
         ) as best_answer_score,
         exists (
           select 1 from posts a
           join posts q on q.id = a.parentid and q.acceptedanswerid = a.id
           where a.owneruserid = c.user_id and a.posttypeid = 2
         ) as has_accepted_answer
  from candidates c
),
-- rank candidates using window functions and also compute percentile
ranked as (
  select bal.*,
         row_number() over (order by composite_score desc nulls last, reputation desc nulls last) as rn,
         rank() over (order by composite_score desc nulls last) as rnk,
         ntile(100) over (order by composite_score desc nulls last) as pct_rank
  from best_answer_lookup bal
)
-- final: top 50 plus a union branch to ensure users with no posts but many badges are included
select r.user_id,
       r.displayname,
       r.reputation,
       r.answer_count,
       r.question_count,
       r.total_answer_score,
       r.badge_points,
       r.top_tag,
       r.answers_for_top_tag,
       r.avg_score_on_top_tag,
       r.avg_seconds_to_accept,
       r.posts_last_6m,
       r.upvotes_last_6m,
       r.composite_score,
       r.quick_summary,
       r.best_answer_id,
       r.best_answer_score,
       r.has_accepted_answer,
       r.rn,
       r.rnk,
       r.pct_rank
from ranked r
where r.rn <= 50

union

select u.id as user_id,
       u.displayname,
       u.reputation,
       0 as answer_count,
       0 as question_count,
       0 as total_answer_score,
       coalesce(b.badge_points,0) as badge_points,
       '<<none>>' as top_tag,
       0 as answers_for_top_tag,
       0.0 as avg_score_on_top_tag,
       1e9 as avg_seconds_to_accept,
       0 as posts_last_6m,
       0 as upvotes_last_6m,
       (case when coalesce(b.badge_points,0) > 0 then coalesce(b.badge_points,0) * 2.0 + ln(u.reputation+10) else ln(u.reputation+10) end) as composite_score,
       concat_ws(' | ', coalesce(u.displayname,'<anon>'), 'rep='||u.reputation::text, 'badges='||coalesce(b.badge_points::text,'0')) as quick_summary,
       null::int as best_answer_id,
       null::int as best_answer_score,
       false as has_accepted_answer,
       null::int as rn,
       null::int as rnk,
       null::int as pct_rank
from users u
left join badge_score b on b.userid = u.id
where coalesce(b.badge_points,0) >= 50
order by composite_score desc NULLS LAST, reputation desc NULLS LAST
limit 20;