with
recent_q as (
  select p.id, p.owneruserid, p.creationdate, p.score, p.viewcount,
         p.title,
         nullif(p.tags,'') as raw_tags,
         regexp_split_to_table(substring(coalesce(p.tags,'') from 2 for greatest(length(coalesce(p.tags,'')) - 2,0)), '><') as tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
),
answers as (
  select a.id, a.parentid as questionid, a.owneruserid, a.creationdate, a.score,
         coalesce(a.body,'') as body,
         case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted,
         (a.creationdate - q.creationdate) as answer_latency
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
),
user_activity as (
  select u.id as userid,
         u.reputation,
         count(distinct r.id) filter (where r.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as q30_posts,
         count(distinct a.id) filter (where a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as a30_posts,
         coalesce(sum(case when a.is_accepted = 1 then 1 else 0 end),0) as accepted_answers_total,
         row_number() over (order by u.reputation desc nulls last) as rep_rank
  from users u
  left join recent_q r on r.owneruserid = u.id
  left join answers a on a.owneruserid = u.id
  group by u.id, u.reputation
),
badge_counts as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
  from badges b
  group by b.userid
),
tag_popularity as (
  select tag, count(*) as questions_count,
         avg(coalesce(rq.score,0)) as avg_q_score,
         max(coalesce(rq.viewcount,0)) as max_views
  from recent_q rq
  group by tag
),
tag_top_contributor as (
  select tp.tag, u.id as userid, u.displayname,
         sum(a.score) as total_answer_score,
         rank() over (partition by tp.tag order by sum(a.score) desc nulls last) as rnk
  from tag_popularity tp
  join recent_q rq on rq.tag = tp.tag
  join answers a on a.questionid = rq.id
  join users u on u.id = a.owneruserid
  group by tp.tag, u.id, u.displayname
),
question_metrics as (
  select q.id as questionid, q.owneruserid, q.creationdate, q.score, q.viewcount, q.acceptedanswerid,
         count(distinct a.owneruserid) as distinct_answerers,
         avg(extract(epoch from a.answer_latency)) as avg_answer_latency_seconds,
         max(a.is_accepted) as has_accepted,
         (select min(a2.creationdate) from posts a2 where a2.parentid = q.id and a2.posttypeid = 2 and a2.id = q.acceptedanswerid) as accepted_answer_date,
         case
           when q.acceptedanswerid is not null
             and ( (select min(a2.creationdate) from posts a2 where a2.parentid = q.id and a2.posttypeid = 2 and a2.id = q.acceptedanswerid) <= q.creationdate + interval '24 hours' )
           then 1 else 0 end as accepted_within_24h
  from posts q
  left join answers a on a.questionid = q.id
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.acceptedanswerid
),
user_combined as (
  select ua.userid,
         ua.reputation,
         ua.q30_posts,
         ua.a30_posts,
         ua.accepted_answers_total,
         coalesce(bc.gold_badges,0) as gold_badges,
         coalesce(bc.silver_badges,0) as silver_badges,
         coalesce(bc.bronze_badges,0) as bronze_badges,
         most_common_tag.tag as top_tag,
         most_common_tag.tag_count
  from user_activity ua
  full outer join badge_counts bc on bc.userid = ua.userid
  left join lateral (
    select tag, count(*) as tag_count
    from recent_q rq
    where rq.owneruserid = ua.userid
    group by tag
    order by count(*) desc nulls last
    limit 1
  ) most_common_tag on true
),
metrics_union as (
  -- first part: tag metrics
  select
    tp.tag as metric_key,
    'tag' as metric_type,
    tp.questions_count as metric_value_num,
    tt.total_answer_score as metric_value_num2,
    tp.avg_q_score as metric_value_real,
    tp.max_views as metric_value_bigint,
    cast(tt.userid as text) as related_id,
    tt.displayname as related_display,
    cast(null as text) as extra
  from tag_popularity tp
  left join tag_top_contributor tt on tt.tag = tp.tag and tt.rnk = 1

  union all

  -- second part: user metrics
  select
    cast(uc.userid as text) as metric_key,
    'user' as metric_type,
    uc.reputation as metric_value_num,
    uc.gold_badges as metric_value_num2,
    uc.silver_badges as metric_value_real,
    uc.bronze_badges as metric_value_bigint,
    cast(uc.userid as text) as related_id,
    coalesce(u.displayname, 'unknown') as related_display,
    uc.top_tag as extra
  from user_combined uc
  join users u on u.id = uc.userid
  where uc.reputation is not null

  union all

  -- third part: stalled question metrics
  select
    cast(qm.questionid as text) as metric_key,
    'stalled_question' as metric_type,
    qm.distinct_answerers as metric_value_num,
    cast(coalesce(qm.avg_answer_latency_seconds,0) as bigint) as metric_value_num2,
    cast(qm.has_accepted as integer) as metric_value_real,
    coalesce(qm.viewcount,0) as metric_value_bigint,
    cast(qm.questionid as text) as related_id,
    (select substring(q2.title from 1 for 120) from posts q2 where q2.id = qm.questionid) as related_display,
    case when qm.accepted_within_24h = 1 then 'accepted_24h' else null end as extra
  from question_metrics qm
  where coalesce(qm.avg_answer_latency_seconds,0) > 48 * 3600
    and coalesce(qm.has_accepted,0) = 0
),
final_ranked as (
  select mu.metric_key,
         mu.metric_type,
         mu.metric_value_num,
         mu.metric_value_num2,
         mu.metric_value_real,
         mu.metric_value_bigint,
         mu.related_id,
         mu.related_display,
         mu.extra,
         row_number() over (partition by mu.metric_type order by mu.metric_value_num desc nulls last, mu.metric_value_num2 desc nulls last) as per_type_rank,
         dense_rank() over (order by coalesce(mu.metric_value_num,0) desc, coalesce(mu.metric_value_num2,0) desc) as global_rank,
         count(*) over (partition by mu.metric_type) as count_per_type
  from metrics_union mu
)
select
  fr.metric_type,
  fr.metric_key,
  fr.metric_value_num,
  fr.metric_value_num2,
  fr.metric_value_real,
  fr.metric_value_bigint,
  fr.related_id,
  left(fr.related_display, 120) as short_display,
  coalesce(fr.extra, 'N/A') as extra_info,
  fr.per_type_rank,
  fr.global_rank,
  fr.count_per_type,
  ((coalesce(fr.metric_value_num,0) * 3)
   + greatest(coalesce(fr.metric_value_num2,0),0)
   + floor(cast(coalesce(fr.metric_value_real,0) as numeric))) as synthetic_score,
  md5(coalesce(fr.metric_type,'') || '|' || coalesce(fr.metric_key,'') || '|' || coalesce(fr.related_id,'')) as row_hash
from final_ranked fr
where (fr.metric_value_num is not null and fr.metric_value_num > 0)
   or (fr.metric_value_num2 is not null and fr.metric_value_num2 > 0)
order by fr.global_rank, fr.metric_type, fr.per_type_rank
limit 100;