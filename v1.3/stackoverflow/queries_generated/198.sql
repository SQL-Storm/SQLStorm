-- {"query": "198.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2178} 
with
-- recent activity window per post
post_activity as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.title,
    p.tags,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    coalesce(p.viewcount,0) as viewcount,
    row_number() over (partition by p.id order by coalesce(p.lastactivitydate,p.creationdate) desc) as rn
  from posts p
),
-- questions only with parsed tag array (Postgres-style split)
question_tags as (
  select
    pa.*,
    case when pa.posttypeid = 1 and pa.tags is not null and length(pa.tags) > 2
      then regexp_split_to_table(substring(pa.tags,2,length(pa.tags)-2),'><')
      else null end as tag
  from post_activity pa
  where pa.posttypeid = 1
),
-- per-question aggregated metrics including first answer delay and accepted answer presence
question_metrics as (
  select
    q.id as question_id,
    q.title,
    q.owneruserid,
    q.creationdate as q_creation,
    q.lastactivitydate as q_last_activity,
    q.score as q_score,
    q.viewcount as q_views,
    count(a.id) filter (where a.posttypeid = 2) as answers_count,
    max(a.score) filter (where a.posttypeid = 2) as best_answer_score,
    bool_or(a.id = q.acceptedanswerid) filter (where a.posttypeid = 2) as has_accepted,
    -- time to first answer (in seconds) via correlated subquery
    (select extract(epoch from min(a2.creationdate) - q.creationdate)
     from posts a2
     where a2.parentid = q.id and a2.posttypeid = 2
    )::numeric as secs_to_first_answer
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id, q.title, q.owneruserid, q.creationdate, q.lastactivitydate, q.score, q.viewcount, q.acceptedanswerid
),
-- user summary with windowed reputation tiers and activity recency buckets
user_summary as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.views,0) as profile_views,
    coalesce(u.upvotes,0) as upvotes,
    coalesce(u.downvotes,0) as downvotes,
    count(b.id) filter (where b.class = 1) as gold_badges,
    count(b.id) filter (where b.class = 2) as silver_badges,
    count(b.id) filter (where b.class = 3) as bronze_badges,
    -- reputation percentile among users (approx using window)
    ntile(100) over (order by u.reputation) as reputation_pct,
    -- recent activity flag
    case when u.lastaccessdate >= now() - interval '30 days' then 'active' else 'inactive' end as recent_flag
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.views, u.upvotes, u.downvotes
),
-- tag popularity: number of questions, avg answers, median views (approx)
tag_stats as (
  select
    t.tagname,
    count(distinct q.id) as questions,
    avg(qm.answers_count) as avg_answers,
    percentile_disc(0.5) within group (order by qm.q_views) as median_views,
    max(qm.best_answer_score) as max_best_answer_score
  from tags t
  left join question_tags qt on qt.tag = t.tagname
  left join posts q on q.id = qt.id and q.posttypeid = 1
  left join question_metrics qm on qm.question_id = q.id
  group by t.tagname
),
-- heavy join of posts, answers, votes, and links to create complicated predicate usage
post_deep as (
  select
    q.id as question_id,
    q.title,
    q.creationdate,
    q.owneruserid,
    qm.answers_count,
    qm.has_accepted,
    qm.secs_to_first_answer,
    a.id as answer_id,
    a.owneruserid as answer_owner,
    a.creationdate as answer_creation,
    a.score as answer_score,
    v.vote_count_up,
    v.vote_count_down,
    pl.linked_count,
    -- complex derived metrics with null logic and expression noise
    (coalesce(a.score,0) * greatest(coalesce(v.vote_count_up,0) - coalesce(v.vote_count_down,0), 0)
      + coalesce(qm.best_answer_score,0) * nullif(qm.answers_count,0)
      + (case when qm.has_accepted then 100 else 0 end)
    ) as quality_index,
    -- text length heuristics
    length(coalesce(q.title,'')) as title_len,
    length(coalesce(a.body::text,'')) as answer_body_len
  from posts q
  left join question_metrics qm on qm.question_id = q.id
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  left join (
    select p.id as postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as vote_count_up,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as vote_count_down
    from posts p
    left join votes v on v.postid = p.id
    group by p.id
  ) v on v.postid = a.id
  left join (
    select pl.postid, count(*) as linked_count
    from postlinks pl
    group by pl.postid
  ) pl on pl.postid = q.id
  where q.posttypeid = 1
),
-- compute per-user responder efficiency using window functions and correlated subqueries
responder_efficiency as (
  select
    u.id as user_id,
    u.displayname,
    count(a.id) filter (where a.posttypeid = 2) as answers_provided,
    avg(a.score) filter (where a.posttypeid = 2) as avg_answer_score,
    percentile_cont(0.5) within group (order by extract(epoch from a.creationdate - q.creationdate)) filter (where a.posttypeid = 2 and a.parentid = q.id) over (partition by u.id) as median_response_secs,
    -- last 90-day activity ratio
    sum(case when a.creationdate >= now() - interval '90 days' then 1 else 0 end) as answers_last_90d
  from users u
  left join posts a on a.owneruserid = u.id and a.posttypeid = 2
  left join posts q on q.id = a.parentid
  group by u.id, u.displayname
),
-- a synthesized heavy query that unions different analytical perspectives and orders by multiple criteria
final_union as (
  select
    'top_questions_by_quality' as kind,
    qd.question_id::text as entity_id,
    qd.title as label,
    qd.quality_index as metric1,
    qd.answers_count as metric2,
    null::text as extra
  from post_deep qd
  where qd.quality_index is not null
  order by qd.quality_index desc
  limit 200

  union all

  select
    'top_tags' as kind,
    t.tagname as entity_id,
    t.tagname as label,
    t.questions::numeric as metric1,
    t.avg_answers::numeric as metric2,
    ('median_views=' || coalesce(t.median_views::text,'0')) as extra
  from tag_stats t
  where t.questions > 50
  order by t.questions desc
  limit 200

  union all

  select
    'top_responders' as kind,
    re.user_id::text as entity_id,
    re.displayname as label,
    coalesce(re.answers_provided,0)::numeric as metric1,
    coalesce(re.avg_answer_score,0)::numeric as metric2,
    ('recent90=' || coalesce(re.answers_last_90d::text,'0')) as extra
  from responder_efficiency re
  where coalesce(re.answers_provided,0) > 10
  order by re.answers_provided desc
  limit 200
)
select
  fu.kind,
  fu.entity_id,
  fu.label,
  fu.metric1,
  fu.metric2,
  fu.extra,
  us.reputation as owner_reputation,
  us.recent_flag,
  -- correlated subquery: show top 3 badges of the owner if numeric entity_id maps to a user
  (select string_agg(b.name || ':' || b.class::text, ', ' order by b.class, b.date desc)
   from badges b
   where (case when fu.kind = 'top_responders' then (b.userid::text = fu.entity_id) else false end)
   limit 3
  ) as top_badges,
  -- sanity check expression using set operator to detect existence of tags in tag_stats
  (case when fu.kind = 'top_tags' and exists (select 1 from tag_stats ts where ts.tagname = fu.entity_id) then true else false end) as tag_verified
from final_union fu
left join users us on us.id = (case when fu.kind = 'top_responders' then fu.entity_id::int else null end)
order by fu.kind, fu.metric1 desc, fu.metric2 desc
limit 500;