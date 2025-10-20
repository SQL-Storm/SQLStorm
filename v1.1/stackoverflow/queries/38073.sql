with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
hot_questions as (
  select p.id as question_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.owneruserid as owner_user_id,
         p.title,
         p.tags,
         coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
    and p.score >= 5
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.score as answer_score,
         a.creationdate as answer_date
  from posts a
  where a.posttypeid = 2
),
top_answerers as (
  select a.question_id,
         a.answerer_id,
         sum(case when a.answer_date >= (select max(creationdate) - interval '90 days' from posts) then 1 else 0 end) as answers_last_90d,
         count(*) as total_answers,
         sum(greatest(a.answer_score, 0)) as positive_score_sum
  from answers a
  group by a.question_id, a.answerer_id
),
tag_expansion as (
  select hq.question_id,
         unnest(string_to_array(substring(hq.tags, 2, length(hq.tags)-2), '><')) as tag
  from hot_questions hq
  where hq.tags is not null and length(hq.tags) > 2
),
question_votes as (
  select v.postid as question_id,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
  from votes v
  join hot_questions hq on hq.question_id = v.postid
  group by v.postid
),
comment_activity as (
  select c.postid as question_id,
         count(*) as comments_count,
         max(c.creationdate) as last_comment_at
  from comments c
  join hot_questions hq on hq.question_id = c.postid
  group by c.postid
),
dup_links as (
  select pl.relatedpostid as canonical_id,
         count(case when pl.linktypeid = 3 then 1 end) as duplicate_count
  from postlinks pl
  group by pl.relatedpostid
),
edit_churn as (
  select ph.postid as question_id,
         count(case when ph.posthistorytypeid in (4,5,6,7,8,9,24) then 1 end) as edit_events,
         count(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20) then 1 end) as mod_events,
         max(ph.creationdate) as last_edit_at
  from posthistory ph
  join hot_questions hq on hq.question_id = ph.postid
  group by ph.postid
),
owner_stats as (
  select u.id as owner_user_id,
         u.reputation,
         u.upvotes,
         u.downvotes,
         u.views,
         count(case when b.class = 1 then 1 end) as gold_badges,
         count(case when b.class = 2 then 1 end) as silver_badges,
         count(case when b.class = 3 then 1 end) as bronze_badges,
         max(u.lastaccessdate) as last_seen
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.reputation, u.upvotes, u.downvotes, u.views
),
tag_popularity as (
  select te.tag,
         sum(hq.viewcount) as total_views,
         sum(hq.score) as total_score,
         count(distinct hq.question_id) as questions_count
  from tag_expansion te
  join hot_questions hq on hq.question_id = te.question_id
  group by te.tag
),
accepted_answer_gap as (
  select q.id as question_id,
         q.creationdate as question_created,
         a.creationdate as accepted_created,
         cast(extract(epoch from (a.creationdate - q.creationdate)) as bigint) as seconds_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
    and q.acceptedanswerid is not null
    and q.id in (select question_id from hot_questions)
),
question_rollup as (
  select
    hq.question_id,
    hq.creationdate,
    hq.score,
    hq.viewcount,
    hq.title,
    hq.answercount,
    qv.upvotes,
    qv.downvotes,
    qv.favorites,
    ca.comments_count,
    ca.last_comment_at,
    ec.edit_events,
    ec.mod_events,
    ec.last_edit_at,
    coalesce(dl.duplicate_count, 0) as duplicate_count,
    o.reputation as owner_reputation,
    o.gold_badges,
    o.silver_badges,
    o.bronze_badges,
    o.last_seen as owner_last_seen,
    aag.seconds_to_accept
  from hot_questions hq
  left join question_votes qv on qv.question_id = hq.question_id
  left join comment_activity ca on ca.question_id = hq.question_id
  left join edit_churn ec on ec.question_id = hq.question_id
  left join dup_links dl on dl.canonical_id = hq.question_id
  left join owner_stats o on o.owner_user_id = (select owneruserid from posts p where p.id = hq.question_id)
  left join accepted_answer_gap aag on aag.question_id = hq.question_id
),
answerer_agg as (
  select
    ta.question_id,
    count(*) as distinct_answerers,
    max(ta.answers_last_90d) as max_answers_last_90d_by_user,
    sum(ta.total_answers) as total_answers_submitted,
    sum(ta.positive_score_sum) as sum_positive_answer_scores
  from top_answerers ta
  group by ta.question_id
),
tag_vector as (
  select te.question_id,
         string_agg(te.tag, ',' order by te.tag) as tag_list
  from tag_expansion te
  group by te.question_id
),
final_rank as (
  select
    qr.question_id,
    qr.title,
    qr.creationdate,
    qr.viewcount,
    qr.score,
    qr.answercount,
    qr.upvotes,
    qr.downvotes,
    qr.favorites,
    qr.comments_count,
    qr.edit_events,
    qr.mod_events,
    qr.duplicate_count,
    qr.owner_reputation,
    qr.gold_badges,
    qr.silver_badges,
    qr.bronze_badges,
    qr.seconds_to_accept,
    aa.distinct_answerers,
    aa.max_answers_last_90d_by_user,
    aa.total_answers_submitted,
    aa.sum_positive_answer_scores,
    tv.tag_list,
    (
      coalesce(qr.viewcount,0) * 0.002
      + coalesce(qr.upvotes,0) * 1.5
      - coalesce(qr.downvotes,0) * 1.0
      + coalesce(qr.favorites,0) * 0.8
      + coalesce(qr.comments_count,0) * 0.2
      + coalesce(qr.edit_events,0) * 0.1
      - coalesce(qr.mod_events,0) * 0.3
      + coalesce(qr.duplicate_count,0) * -2.0
      + coalesce(aa.distinct_answerers,0) * 1.0
      + coalesce(aa.sum_positive_answer_scores,0) * 0.5
      + case when qr.seconds_to_accept is not null then greatest(0, 86400*7 - qr.seconds_to_accept) / 86400.0 else 0 end
      + least(coalesce(qr.owner_reputation,0) / 1000.0, 10)
    ) as bench_score
  from question_rollup qr
  left join answerer_agg aa on aa.question_id = qr.question_id
  left join tag_vector tv on tv.question_id = qr.question_id
)
select
  fr.question_id,
  fr.title,
  fr.creationdate,
  fr.tag_list,
  fr.viewcount,
  fr.score,
  fr.answercount,
  fr.upvotes,
  fr.downvotes,
  fr.favorites,
  fr.comments_count,
  fr.edit_events,
  fr.mod_events,
  fr.duplicate_count,
  fr.owner_reputation,
  fr.gold_badges,
  fr.silver_badges,
  fr.bronze_badges,
  fr.seconds_to_accept,
  fr.distinct_answerers,
  fr.max_answers_last_90d_by_user,
  fr.total_answers_submitted,
  fr.sum_positive_answer_scores,
  fr.bench_score,
  rank() over (order by fr.bench_score desc, fr.viewcount desc, fr.upvotes desc) as bench_rank
from final_rank fr
where fr.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
order by bench_rank
limit 200;