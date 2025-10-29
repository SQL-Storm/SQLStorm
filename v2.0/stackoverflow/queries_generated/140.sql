-- {"query": "140.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2684} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as region_hint,
         dense_rank() over (order by u.creationdate desc) as recency_rank
  from users u
),
active_posts as (
  select p.id,
         p.posttypeid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.closeddate,
         p.communityowneddate,
         case when p.posttypeid = 1 then 1 else 0 end as is_question,
         case when p.posttypeid = 2 then 1 else 0 end as is_answer
  from posts p
  where p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts)
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
         min(v.creationdate) as first_vote_at,
         max(v.creationdate) as last_vote_at,
         count(*) as total_votes
  from votes v
  where v.creationdate >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts)
  group by v.postid
),
comments_agg as (
  select c.postid,
         count(*) as comment_count,
         sum(case when c.score >= 5 then 1 else 0 end) as high_score_comments,
         max(c.creationdate) as last_comment_at
  from comments c
  where c.creationdate >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts)
  group by c.postid
),
postlinks_agg as (
  select pl.postid,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
         count(*) as total_links
  from postlinks pl
  group by pl.postid
),
closed_reasons as (
  select ph.postid,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
         max(case
               when ph.posthistorytypeid = 10 then
                 try_cast(nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '') as int)
               else null
             end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
badges_agg as (
  select b.userid,
         count(*) as badge_count,
         sum(case when b.class = 1 then 1 else 0 end) as gold_count,
         sum(case when b.class = 2 then 1 else 0 end) as silver_count,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
tag_explode as (
  select p.id as post_id,
         lower(trim(tg)) as tag
  from active_posts p
  cross join lateral unnest(
    case
      when p.tags is null then array[]::varchar[]
      when length(p.tags) <= 2 then array[]::varchar[]
      else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
    end
  ) as tg
),
tag_stats as (
  select te.post_id,
         count(*) as tag_count,
         string_agg(te.tag, ',' order by te.tag) as tag_list,
         sum(case when te.tag like '%sql%' then 1 else 0 end) as has_sqlish
  from tag_explode te
  group by te.post_id
),
user_activity as (
  select ap.owneruserid as user_id,
         count(*) filter (where ap.is_question = 1) as q_count,
         count(*) filter (where ap.is_answer = 1) as a_count,
         sum(coalesce(va.upvotes,0)) as user_upvotes_received,
         sum(coalesce(va.downvotes,0)) as user_downvotes_received,
         max(ap.creationdate) as last_post_at
  from active_posts ap
  left join votes_agg va on va.postid = ap.id
  group by ap.owneruserid
),
question_answer_pairs as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as question_date,
         q.score as question_score,
         q.viewcount as question_views,
         q.title as question_title,
         q.tags as question_tags,
         q.acceptedanswerid,
         count(a.id) as answer_count,
         max(a.creationdate) as last_answer_at
  from active_posts q
  left join posts a
    on a.parentid = q.id
   and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.acceptedanswerid
),
answer_latency as (
  select qap.question_id,
         case
           when qap.answer_count > 0 then
             avg(extract(epoch from (a.creationdate - qap.question_date)) / 60.0)
           else null
         end as avg_answer_minutes,
         min(extract(epoch from (a.creationdate - qap.question_date)) / 60.0) as first_answer_minutes,
         max(extract(epoch from (a.creationdate - qap.question_date)) / 60.0) as last_answer_minutes
  from question_answer_pairs qap
  left join posts a
    on a.parentid = qap.question_id
   and a.posttypeid = 2
  group by qap.question_id, qap.answer_count, qap.question_date
),
accepted_answer_stats as (
  select q.id as question_id,
         aa.id as accepted_id,
         aa.owneruserid as answerer_id,
         aa.score as accepted_score,
         extract(epoch from (aa.creationdate - q.creationdate))/60.0 as accepted_after_minutes
  from posts q
  join posts aa on aa.id = q.acceptedanswerid
  where q.posttypeid = 1
),
ranked_questions as (
  select
    qap.question_id,
    qap.asker_id,
    qap.question_date,
    qap.question_score,
    qap.question_views,
    qap.question_title,
    coalesce(ts.tag_count, 0) as tag_count,
    ts.tag_list,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(va.bounty_total,0) as bounty_total,
    qap.answer_count,
    al.avg_answer_minutes,
    al.first_answer_minutes,
    coalesce(cl.last_close_reason_id, 0) as last_close_reason_id,
    row_number() over (order by
      coalesce(va.bounty_total,0) desc,
      coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc,
      qap.question_views desc,
      qap.answer_count desc,
      qap.question_date desc
    ) as perf_rank
  from question_answer_pairs qap
  left join votes_agg va on va.postid = qap.question_id
  left join tag_stats ts on ts.post_id = qap.question_id
  left join answer_latency al on al.question_id = qap.question_id
  left join closed_reasons cl on cl.postid = qap.question_id
),
user_quality as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    coalesce(ua.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(ua.user_upvotes_received,0) as up_rcv,
    coalesce(ua.user_downvotes_received,0) as dn_rcv,
    coalesce(b.badge_count,0) as badge_count,
    coalesce(b.gold_count,0) as gold_count,
    coalesce(b.silver_count,0) as silver_count,
    coalesce(b.bronze_count,0) as bronze_count,
    case
      when coalesce(ua.a_count,0) = 0 then null
      else round((coalesce(ua.user_upvotes_received,0)::numeric - coalesce(ua.user_downvotes_received,0)) / nullif(ua.a_count,0), 3)
    end as net_votes_per_answer
  from users u
  left join user_activity ua on ua.user_id = u.id
  left join badges_agg b on b.userid = u.id
),
final as (
  select
    rq.perf_rank,
    rq.question_id,
    rq.question_title,
    rq.question_date,
    rq.question_score,
    rq.question_views,
    rq.answer_count,
    rq.tag_count,
    rq.tag_list,
    rq.upvotes,
    rq.downvotes,
    rq.favorites,
    rq.bounty_total,
    rq.avg_answer_minutes,
    rq.first_answer_minutes,
    rq.last_close_reason_id,
    uk.displayname as asker_name,
    uk.reputation as asker_rep,
    uq.q_count as asker_q_count,
    uq.a_count as asker_a_count,
    uq.badge_count as asker_badges,
    uq.gold_count as asker_gold,
    uq.silver_count as asker_silver,
    uq.bronze_count as asker_bronze,
    uq.net_votes_per_answer as asker_net_votes_per_answer,
    case when coalesce(ts.has_sqlish,0) > 0 then 1 else 0 end as is_sql_related,
    coalesce(pl.total_links,0) as total_links,
    coalesce(pl.duplicate_count,0) as duplicate_links,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.high_score_comments,0) as high_score_comments,
    ca.last_comment_at,
    case
      when rq.bounty_total > 0 then 'Bounty'
      when rq.favorites > 25 then 'Popular'
      when rq.question_views > 10000 then 'HighViews'
      when rq.answer_count = 0 and rq.question_score <= 0 then 'UnansweredLowScore'
      when rq.last_close_reason_id in (101,102,103,104,105) then 'Closed'
      else 'Standard'
    end as classification
  from ranked_questions rq
  left join posts q on q.id = rq.question_id
  left join tag_stats ts on ts.post_id = rq.question_id
  left join postlinks_agg pl on pl.postid = rq.question_id
  left join comments_agg ca on ca.postid = rq.question_id
  left join user_quality uq on uq.user_id = rq.asker_id
  left join users uk on uk.id = rq.asker_id
  where
    -- complicated predicate mixing nulls, regex on title, and tag presence
    (
      rq.bounty_total > 0
      or rq.favorites >= 10
      or (rq.answer_count = 0 and coalesce(rq.avg_answer_minutes, 999999) > 1440)
      or (rq.tag_list ~* '(^|,)(performance|benchmark|tuning)(,|$)')
      or (q.title is not null and regexp_replace(lower(q.title), '[^a-z0-9 ]', '', 'g') like any (array['%optimiz%','%index%','%query%'])
         )
    )
)
select *
from final
qualify row_number() over (
  partition by classification
  order by perf_rank
) <= 50
order by classification, perf_rank;