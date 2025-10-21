with recent_active_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate
  from users u
  where u.lastaccessdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
),
tagged_questions as (
  select p.id as question_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.owneruserid,
         p.tags,
         string_to_array(substr(p.tags, 2, length(p.tags) - 2), '><') as tag_array
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
expanded_tags as (
  select tq.question_id, tq.creationdate, tq.score, tq.viewcount, tq.owneruserid, unnest(tq.tag_array) as tagname
  from tagged_questions tq
),
top_200_tags as (
  select et.tagname, count(*) as q_count
  from expanded_tags et
  group by et.tagname
  order by q_count desc
  limit 200
),
answers_last_year as (
  select a.id as answer_id, a.parentid as question_id, a.owneruserid as answerer_id, a.score as answer_score, a.creationdate
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
votes_last_year as (
  select v.postid, v.votetypeid, v.userid, v.creationdate
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
question_updown as (
  select v.postid as question_id,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes
  from votes_last_year v
  join posts p on p.id = v.postid and p.posttypeid = 1
  group by v.postid
),
answer_updown as (
  select v.postid as answer_id,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes
  from votes_last_year v
  join posts a on a.id = v.postid and a.posttypeid = 2
  group by v.postid
),
comment_counts as (
  select c.postid,
         count(*) as comment_count,
         sum(case when c.score > 0 then 1 else 0 end) as pos_comments
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by c.postid
),
badge_activity as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) as total_badges
  from badges b
  where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by b.userid
),
question_answer_stats as (
  select tq.id as question_id,
         tq.creationdate,
         tq.score as question_score,
         tq.viewcount,
         tq.owneruserid as asker_id,
         coalesce(qa.upvotes,0) as q_upvotes,
         coalesce(qa.downvotes,0) as q_downvotes,
         coalesce(ccq.comment_count,0) as q_comments,
         coalesce(cca.comment_count,0) as a_comments_total,
         count(a.answer_id) as answers_count,
         avg(a.answer_score) as avg_answer_score,
         max(a.answer_score) as max_answer_score,
         sum(coalesce(au.upvotes,0)) as answer_upvotes_total,
         sum(coalesce(au.downvotes,0)) as answer_downvotes_total,
         min(a.creationdate) as first_answer_time,
         max(a.creationdate) as last_answer_time
  from posts tq
  left join question_updown qa on qa.question_id = tq.id
  left join comment_counts ccq on ccq.postid = tq.id
  left join answers_last_year a on a.question_id = tq.id
  left join answer_updown au on au.answer_id = a.answer_id
  left join comment_counts cca on cca.postid = a.answer_id
  where tq.posttypeid = 1
    and tq.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by tq.id, tq.creationdate, tq.score, tq.viewcount, tq.owneruserid, qa.upvotes, qa.downvotes, ccq.comment_count, cca.comment_count
),
question_tag_rollup as (
  select et.question_id,
         array_agg(et.tagname order by et.tagname) as tags_sorted,
         array_agg(et.tagname) filter (where t.tagname is not null) as tags_top200
  from expanded_tags et
  left join top_200_tags t on t.tagname = et.tagname
  group by et.question_id
),
user_activity as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         coalesce(b.total_badges,0) as badges_last_year,
         coalesce(b.gold_badges,0) as gold_badges_last_year,
         coalesce(b.silver_badges,0) as silver_badges_last_year,
         coalesce(b.bronze_badges,0) as bronze_badges_last_year,
         u.upvotes as lifetime_upvotes,
         u.downvotes as lifetime_downvotes,
         u.views as profile_views
  from users u
  left join badge_activity b on b.userid = u.id
),
dupe_links as (
  select pl.postid as dup_post_id, count(*) as dup_count
  from postlinks pl
  where pl.linktypeid = 3
    and pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by pl.postid
),
hot_history as (
  select ph.postid,
         sum(case when ph.posthistorytypeid = 52 then 1 else 0 end) as hot_adds,
         sum(case when ph.posthistorytypeid = 53 then 1 else 0 end) as hot_removes,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (52,53)) as last_hot_event
  from posthistory ph
  join posts p on p.id = ph.postid and p.posttypeid = 1
  where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by ph.postid
),
accept_stats as (
  select q.id as question_id,
         case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer
  from posts q
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
owner_recent as (
  select u.user_id, u.displayname, u.reputation
  from recent_active_users u
),
question_owner as (
  select q.id as question_id, u.user_id, u.displayname as owner_name, u.reputation as owner_rep
  from posts q
  left join owner_recent u on u.user_id = q.owneruserid
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
answerer_engagement as (
  select a.question_id,
         count(distinct a.answerer_id) as distinct_answerers,
         count(a.answer_id) filter (where ra.user_id is not null) as answers_by_recent_users
  from answers_last_year a
  left join recent_active_users ra on ra.user_id = a.answerer_id
  group by a.question_id
),
score_velocity as (
  select q.id as question_id,
         extract(epoch from (coalesce(q.lastactivitydate,q.creationdate) - q.creationdate)) / 3600.0 as hours_active,
         q.score as score_total,
         case when extract(epoch from (coalesce(q.lastactivitydate,q.creationdate) - q.creationdate)) > 0
              then q.score / (extract(epoch from (coalesce(q.lastactivitydate,q.creationdate) - q.creationdate)) / 3600.0)
              else null end as score_per_hour
  from posts q
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
final as (
  select
    qas.question_id,
    qo.owner_name,
    qo.owner_rep,
    ua.badges_last_year,
    ua.gold_badges_last_year,
    ua.silver_badges_last_year,
    ua.bronze_badges_last_year,
    qas.creationdate as question_created,
    qas.question_score,
    qas.viewcount,
    qas.q_upvotes,
    qas.q_downvotes,
    qas.q_comments,
    qas.answers_count,
    qas.avg_answer_score,
    qas.max_answer_score,
    qas.answer_upvotes_total,
    qas.answer_downvotes_total,
    ae.distinct_answerers,
    ae.answers_by_recent_users,
    ac.has_accepted_answer,
    dl.dup_count,
    hh.hot_adds,
    hh.hot_removes,
    hh.last_hot_event,
    sv.hours_active,
    sv.score_total,
    sv.score_per_hour,
    qt.tags_sorted,
    qt.tags_top200
  from question_answer_stats qas
  left join question_owner qo on qo.question_id = qas.question_id
  left join user_activity ua on ua.user_id = qo.user_id
  left join accept_stats ac on ac.question_id = qas.question_id
  left join dupe_links dl on dl.dup_post_id = qas.question_id
  left join hot_history hh on hh.postid = qas.question_id
  left join score_velocity sv on sv.question_id = qas.question_id
  left join question_tag_rollup qt on qt.question_id = qas.question_id
  left join answerer_engagement ae on ae.question_id = qas.question_id
)
select *
from final
where viewcount is not null
order by
  coalesce(hot_adds,0) desc,
  has_accepted_answer desc,
  answers_count desc,
  score_per_hour desc nulls last,
  viewcount desc
limit 500;