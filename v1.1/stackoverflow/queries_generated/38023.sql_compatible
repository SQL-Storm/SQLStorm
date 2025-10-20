with recent_active_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         u.location,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(distinct date_trunc('day', p.creationdate)) as active_post_days_90
  from users u
  left join badges b on b.userid = u.id and b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  left join posts p on p.owneruserid = u.id and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
  where u.lastaccessdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days'
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.location
),
question_core as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as question_date,
         q.score as question_score,
         q.viewcount,
         q.title,
         q.tags,
         q.answercount,
         q.acceptedanswerid,
         q.closeddate,
         q.communityowneddate
  from posts q
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
answer_core as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.creationdate as answer_date,
         a.score as answer_score
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
comment_activity as (
  select c.postid,
         count(*) as comment_count,
         avg(c.score) as avg_comment_score,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by c.postid
),
votes_agg as (
  select v.postid,
         count(*) filter (where v.votetypeid = 2) as upvotes,
         count(*) filter (where v.votetypeid = 3) as downvotes,
         count(*) filter (where v.votetypeid = 5) as favorites,
         sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by v.postid
),
links_agg as (
  select pl.postid,
         count(*) filter (where pl.linktypeid = 1) as linked_count,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links
  from postlinks pl
  where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by pl.postid
),
hot_streaks as (
  select q.question_id,
         min(a.answer_date) as first_answer_time,
         count(*) as answers_last_year,
         count(*) filter (where a.answer_date <= q.question_date + interval '24 hours') as answers_24h,
         count(*) filter (where a.answer_date <= q.question_date + interval '7 days') as answers_7d
  from question_core q
  left join answer_core a on a.question_id = q.question_id
  group by q.question_id, q.question_date
),
accepted_info as (
  select q.question_id,
         case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
         min(a.answer_date) filter (where a.answer_id = q.acceptedanswerid) as accepted_date
  from question_core q
  left join answer_core a on a.answer_id = q.acceptedanswerid
  group by q.question_id, q.acceptedanswerid
),
tag_expansion as (
  select q.question_id,
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from question_core q
  where q.tags is not null and q.tags like '<%>'
),
tag_stats as (
  select t.tagname as tag,
         count(distinct te.question_id) as tag_question_count,
         sum(qc.viewcount) as tag_views,
         avg(qc.question_score) as tag_avg_score
  from tag_expansion te
  join question_core qc on qc.question_id = te.question_id
  join tags t on t.tagname = te.tag
  group by t.tagname
),
user_engagement as (
  select q.question_id,
         q.asker_id,
         rau.displayname as asker_name,
         rau.reputation as asker_reputation,
         rau.gold_badges,
         rau.silver_badges,
         rau.bronze_badges,
         rau.active_post_days_90
  from question_core q
  left join recent_active_users rau on rau.user_id = q.asker_id
),
posthistory_flags as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as moderation_events,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopened_at
  from posthistory ph
  where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by ph.postid
),
question_quality as (
  select q.question_id,
         coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
         coalesce(v.favorites,0) as favorites,
         coalesce(v.bounty_total,0) as bounty_total,
         coalesce(ca.comment_count,0) as comments_count,
         coalesce(ca.avg_comment_score,0) as avg_comment_score,
         coalesce(la.linked_count,0) as linked_count,
         coalesce(la.duplicate_links,0) as duplicate_links,
         ph.moderation_events,
         ph.closed_at,
         ph.reopened_at
  from question_core q
  left join votes_agg v on v.postid = q.question_id
  left join comment_activity ca on ca.postid = q.question_id
  left join links_agg la on la.postid = q.question_id
  left join posthistory_flags ph on ph.postid = q.question_id
),
answer_quality as (
  select a.answer_id,
         a.question_id,
         a.answerer_id,
         a.answer_score,
         coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
         coalesce(v.favorites,0) as favorites,
         coalesce(ca.comment_count,0) as comments_count
  from answer_core a
  left join votes_agg v on v.postid = a.answer_id
  left join comment_activity ca on ca.postid = a.answer_id
),
best_answer as (
  select aq.question_id,
         max(aq.net_votes) as best_answer_net_votes,
         max(aq.answer_score) as best_answer_score
  from answer_quality aq
  group by aq.question_id
),
question_rank as (
  select q.question_id,
         q.title,
         q.tags,
         q.question_score,
         q.viewcount,
         hs.answers_last_year,
         hs.answers_24h,
         hs.answers_7d,
         ai.has_accepted,
         ai.accepted_date,
         qq.net_votes,
         qq.favorites,
         qq.bounty_total,
         qq.comments_count,
         qq.avg_comment_score,
         qq.linked_count,
         qq.duplicate_links,
         qq.moderation_events,
         qq.closed_at,
         qq.reopened_at,
         ba.best_answer_net_votes,
         ba.best_answer_score,
         ue.asker_id,
         ue.asker_name,
         ue.asker_reputation,
         ue.gold_badges,
         ue.silver_badges,
         ue.bronze_badges,
         ue.active_post_days_90,
         greatest(
           0,
           0.30 * coalesce(q.viewcount,0) / nullif((hs.answers_last_year + 10),0) +
           0.25 * coalesce(qq.net_votes,0) +
           0.15 * coalesce(qq.favorites,0) +
           0.10 * coalesce(qq.linked_count,0) -
           0.10 * coalesce(qq.duplicate_links,0) +
           0.10 * coalesce(ba.best_answer_net_votes,0)
         ) as perf_score
  from question_core q
  left join hot_streaks hs on hs.question_id = q.question_id
  left join accepted_info ai on ai.question_id = q.question_id
  left join question_quality qq on qq.question_id = q.question_id
  left join best_answer ba on ba.question_id = q.question_id
  left join user_engagement ue on ue.question_id = q.question_id
)
select
  qr.question_id,
  qr.title,
  qr.tags,
  qr.asker_id,
  qr.asker_name,
  qr.asker_reputation,
  qr.gold_badges,
  qr.silver_badges,
  qr.bronze_badges,
  qr.active_post_days_90,
  qr.question_score,
  qr.viewcount,
  qr.answers_last_year,
  qr.answers_24h,
  qr.answers_7d,
  qr.has_accepted,
  qr.accepted_date,
  qr.net_votes,
  qr.favorites,
  qr.bounty_total,
  qr.comments_count,
  qr.avg_comment_score,
  qr.linked_count,
  qr.duplicate_links,
  qr.moderation_events,
  qr.closed_at,
  qr.reopened_at,
  qr.best_answer_net_votes,
  qr.best_answer_score,
  qr.perf_score
from question_rank qr
where qr.viewcount is not null
order by qr.perf_score desc nulls last, qr.viewcount desc
limit 200;