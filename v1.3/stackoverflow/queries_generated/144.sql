-- {"query": "144.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2298} 
with
-- recent questions and derived fields
recent_q as (
  select p.id, p.title, p.creationdate, p.owneruserid, p.viewcount, p.score,
         p.answercount, p.favoritecount,
         coalesce(p.tags,'') as tags,
         -- extract first tag for simple grouping
         (case when p.tags is null or p.tags = '' then null
               else (string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><'))[1]
          end) as first_tag,
         p.lastactivitydate
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '1 year'
),

-- explode tags to one row per tag per question
q_tags as (
  select q.id as question_id,
         trim(t) as tag
  from recent_q q
  cross join lateral (
    select unnest(string_to_array(substring(q.tags from 2 for char_length(q.tags)-2), '><')) as t
  ) s
),

-- aggregate answers and votes per question
ans_votes as (
  select a.parentid as question_id,
         count(*) filter (where a.posttypeid = 2) as answers_total,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_on_answers,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_on_answers,
         avg(a.score) filter (where a.posttypeid = 2) as avg_answer_score,
         max(a.score) filter (where a.posttypeid = 2) as max_answer_score
  from posts a
  left join votes v on v.postid = a.id
  where a.posttypeid = 2
  group by a.parentid
),

-- top answerer per question using window functions and correlated scoring
top_answerers as (
  select question_id, answer_id, owneruserid as answerer_id, answer_score, rn
  from (
    select a.parentid as question_id, a.id as answer_id, a.owneruserid,
           a.score as answer_score,
           rank() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as rn
    from posts a
    where a.posttypeid = 2
  ) x
  where rn = 1
),

-- user badges counts in last year per user and bronze/silver/gold breakdown
user_badges as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold,
         sum(case when b.class = 2 then 1 else 0 end) as silver,
         sum(case when b.class = 3 then 1 else 0 end) as bronze,
         bool_or(b.tagbased) as has_tag_badge
  from badges b
  where b.date >= now() - interval '1 year'
  group by b.userid
),

-- user activity spikes: number of posts and comments in last 30 days
user_activity as (
  select u.id as user_id,
         coalesce(p_count,0) as posts_30d,
         coalesce(c_count,0) as comments_30d,
         u.reputation
  from users u
  left join (
    select owneruserid, count(*) as p_count
    from posts
    where creationdate >= now() - interval '30 days'
      and owneruserid is not null
    group by owneruserid
  ) p on p.owneruserid = u.id
  left join (
    select userid, count(*) as c_count
    from comments
    where creationdate >= now() - interval '30 days'
      and userid is not null
    group by userid
  ) c on c.userid = u.id
),

-- compile tag popularity and interestingness using set operators to include tag wikis as well
tag_sources as (
  select t.tagname as tag, t.id as tag_id from tags t
  union
  select distinct unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><')) as tag, null::int as tag_id
  from posts p
  where p.posttypeid = 1
),

tag_stats as (
  select ts.tag,
         count(distinct qt.question_id) as questions_with_tag,
         sum(rq.viewcount) as total_views_on_tagged_questions,
         avg(rq.score) as avg_question_score,
         max(rq.answercount) as max_answers_on_question,
         row_number() over (order by count(distinct qt.question_id) desc nulls last) as popularity_rank
  from tag_sources ts
  left join q_tags qt on qt.tag = ts.tag
  left join recent_q rq on rq.id = qt.question_id
  group by ts.tag
),

-- get last activity's history reason via PostHistory correlated subquery (may be null)
last_activity_reason as (
  select p.id as postid,
         ph.posthistorytypeid,
         ph.creationdate as ph_date,
         ph.userdisplayname,
         ph.comment as ph_comment
  from posts p
  left join lateral (
    select ph2.posthistorytypeid, ph2.creationdate, ph2.userdisplayname, ph2.comment
    from posthistory ph2
    where ph2.postid = p.id
    order by ph2.creationdate desc
    limit 1
  ) ph on true
  where p.posttypeid = 1
),

-- final assembled per-question metrics with complex predicates and NULL logic
question_metrics as (
  select rq.*,
         coalesce(av.answers_total, rq.answercount, 0) as answers_total_calc,
         coalesce(av.upvotes_on_answers,0) as upvotes_on_answers,
         coalesce(av.downvotes_on_answers,0) as downvotes_on_answers,
         coalesce(av.avg_answer_score,0) as avg_answer_score,
         coalesce(av.max_answer_score,0) as max_answer_score,
         ta.answerer_id as top_answerer_id,
         ub.total_badges as top_answerer_badges,
         ua.posts_30d as top_answerer_posts_30d,
         ls.posthistorytypeid as last_history_type,
         ls.ph_comment as last_history_comment,
         ts.popularity_rank as tag_pop_rank,
         ts.questions_with_tag,
         -- complex score combining views, recency, answer quality, badges, and tag popularity
         (
           (coalesce(rq.viewcount,0)::numeric * 0.0001)
           + (coalesce(av.avg_answer_score,0) * 0.5)
           + (coalesce(ub.gold,0) * 1.5)
           + (case when rq.creationdate > now() - interval '30 days' then 5 else 0 end)
           + (case when ts.popularity_rank is null then 0 else greatest(0, 100 - ts.popularity_rank)::numeric/100 end)
           - (coalesce(av.downvotes_on_answers,0) * 0.2)
         ) as composite_hotness
  from recent_q rq
  left join ans_votes av on av.question_id = rq.id
  left join top_answerers ta on ta.question_id = rq.id
  left join user_badges ub on ub.userid = ta.answerer_id
  left join user_activity ua on ua.user_id = ta.answerer_id
  left join last_activity_reason ls on ls.postid = rq.id
  left join tag_stats ts on ts.tag = rq.first_tag
),

-- rank and window over composite score and tag
ranked_questions as (
  select qm.*,
         rank() over (order by composite_hotness desc nulls last) as global_rank,
         rank() over (partition by first_tag order by composite_hotness desc nulls last) as tag_rank,
         dense_rank() over (order by coalesce(answers_total_calc,0) desc) as answer_density_rank
  from question_metrics qm
)

select
  rq.id,
  rq.title,
  rq.creationdate,
  rq.first_tag,
  rq.viewcount,
  rq.score,
  rq.answers_total_calc,
  rq.upvotes_on_answers,
  rq.downvotes_on_answers,
  round(rq.avg_answer_score::numeric,2) as avg_answer_score,
  rq.max_answer_score,
  rq.top_answerer_id,
  coalesce(rq.top_answerer_badges,0) as top_answerer_badges,
  coalesce(rq.top_answerer_posts_30d,0) as top_answerer_posts_30d,
  rq.last_history_type,
  rq.last_history_comment,
  rq.questions_with_tag,
  rq.popularity_rank,
  round(rq.composite_hotness::numeric,4) as composite_hotness,
  rq.global_rank,
  rq.tag_rank,
  rq.answer_density_rank,
  -- example of correlated subquery: number of duplicates pointing to this question (LinkTypeId=3)
  (select count(*) from postlinks pl where pl.relatedpostid = rq.id and pl.linktypeid = 3) as duplicate_count,
  -- single correlated aggregate with NULL logic: recent distinct editors in last 90 days
  (select count(distinct ph.userId) from posthistory ph where ph.postid = rq.id and ph.creationdate >= now() - interval '90 days' and ph.userid is not null) as distinct_recent_editors,
  -- string expression: abbreviated tags list
  (case when rq.tags = '' then '(none)' else left(replace(replace(rq.tags,'><',', '),'<>',''), 200) end) as tag_list_preview
from ranked_questions rq
where rq.composite_hotness is not null
  and rq.global_rank <= 500
order by rq.composite_hotness desc, rq.viewcount desc
limit 250;