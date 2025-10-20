with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (
    select date_trunc('month', max(creationdate)) - interval '12 months' from users
  )
), q_posts as (
  select p.id as question_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.owneruserid as owner_user_id,
         p.tags,
         coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (
      select date_trunc('month', max(creationdate)) - interval '24 months' from posts
    )
), a_posts as (
  select p.id as answer_id,
         p.parentid as question_id,
         p.creationdate as answer_creationdate,
         p.score as answer_score,
         p.owneruserid as answer_user_id
  from posts p
  where p.posttypeid = 2
), first_answers as (
  select a.question_id,
         min(a.answer_creationdate) as first_answer_time
  from a_posts a
  group by a.question_id
), q_activity as (
  select q.question_id,
         q.creationdate as question_time,
         fa.first_answer_time,
         cast(extract(epoch from (fa.first_answer_time - q.creationdate)) as bigint) as time_to_first_answer_sec,
         q.score,
         q.viewcount,
         q.tags,
         q.answercount
  from q_posts q
  left join first_answers fa on fa.question_id = q.question_id
), tag_expanded as (
  select qa.question_id,
         unnest(string_to_array(substring(qa.tags, 2, length(qa.tags)-2), '><')) as tag
  from q_activity qa
  where qa.tags is not null and qa.tags like '<%>'
), tag_stats as (
  select te.tag,
         count(*) as questions,
         avg(qa.score) as avg_score,
         avg(qa.viewcount) as avg_views,
         percentile_cont(0.5) within group (order by qa.viewcount) as p50_views,
         percentile_cont(0.9) within group (order by qa.viewcount) as p90_views,
         percentile_cont(0.99) within group (order by qa.viewcount) as p99_views,
         avg(qa.time_to_first_answer_sec) as avg_ttf_answer_sec,
         percentile_cont(0.5) within group (order by qa.time_to_first_answer_sec) as p50_ttf_answer_sec
  from tag_expanded te
  join q_activity qa on qa.question_id = te.question_id
  group by te.tag
  having count(*) >= 50
), votes_agg as (
  select v.postid as question_id,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
  from votes v
  join q_posts q on q.question_id = v.postid
  group by v.postid
), comments_agg as (
  select c.postid as question_id,
         count(*) as comments,
         max(c.score) as max_comment_score
  from comments c
  join q_posts q on q.question_id = c.postid
  group by c.postid
), link_dupes as (
  select pl.postid as question_id,
         count(case when pl.linktypeid = 3 then 1 end) as duplicate_links,
         count(case when pl.linktypeid = 1 then 1 end) as linked_links
  from postlinks pl
  join q_posts q on q.question_id = pl.postid
  group by pl.postid
), closures as (
  select ph.postid as question_id,
         min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_time,
         max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_time,
         count(case when ph.posthistorytypeid = 10 then 1 end) as close_events,
         count(case when ph.posthistorytypeid = 11 then 1 end) as reopen_events
  from posthistory ph
  join q_posts q on q.question_id = ph.postid
  group by ph.postid
), asker_stats as (
  select q.owner_user_id as user_id,
         count(*) as questions_asked,
         avg(q.score) as avg_q_score,
         avg(q.viewcount) as avg_q_views
  from q_posts q
  where q.owner_user_id is not null
  group by q.owner_user_id
), quality_score as (
  select qa.question_id,
         coalesce(v.upvotes,0) as upvotes,
         coalesce(v.downvotes,0) as downvotes,
         coalesce(v.favorites,0) as favorites,
         coalesce(ca.comments,0) as comments,
         coalesce(ca.max_comment_score,0) as max_comment_score,
         coalesce(ld.duplicate_links,0) as duplicate_links,
         coalesce(ld.linked_links,0) as linked_links,
         coalesce(cl.close_events,0) as close_events,
         coalesce(cl.reopen_events,0) as reopen_events,
         qa.viewcount,
         qa.score,
         qa.time_to_first_answer_sec,
         cast(
           1.0 * coalesce(v.upvotes,0)
           - 0.8 * coalesce(v.downvotes,0)
           + 0.5 * coalesce(v.favorites,0)
           + 0.02 * qa.viewcount
           - 0.1 * coalesce(cl.close_events,0)
           - 0.05 * coalesce(ld.duplicate_links,0)
           + 0.03 * coalesce(ld.linked_links,0)
           - 0.0002 * greatest(coalesce(qa.time_to_first_answer_sec, 0), 0)
         as numeric(14,4)) as quality_score
  from q_activity qa
  left join votes_agg v on v.question_id = qa.question_id
  left join comments_agg ca on ca.question_id = qa.question_id
  left join link_dupes ld on ld.question_id = qa.question_id
  left join closures cl on cl.question_id = qa.question_id
), tag_quality as (
  select te.tag,
         count(*) as n,
         avg(qs.quality_score) as avg_quality,
         percentile_cont(0.9) within group (order by qs.quality_score) as p90_quality
  from tag_expanded te
  join quality_score qs on qs.question_id = te.question_id
  group by te.tag
  having count(*) >= 50
), user_influence as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         coalesce(sum(case when p.posttypeid = 1 then p.score else 0 end),0) as total_q_score,
         coalesce(sum(case when p.posttypeid = 2 then p.score else 0 end),0) as total_a_score,
         coalesce(sum(p.viewcount),0) as total_views,
         sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
         sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation
), top_tags as (
  select ts.tag,
         ts.questions,
         ts.avg_views,
         tq.avg_quality,
         row_number() over (order by ts.questions desc, ts.avg_views desc) as rn
  from tag_stats ts
  join tag_quality tq on tq.tag = ts.tag
), global_percentiles as (
  select
    percentile_cont(0.9) within group (order by viewcount) as g_p90_view,
    percentile_cont(0.5) within group (order by viewcount) as g_p50_view,
    percentile_cont(0.2) within group (order by viewcount) as g_p20_view
  from q_activity
), question_buckets as (
  select qa.question_id,
         case
           when qa.viewcount >= gp.g_p90_view then 'very_high'
           when qa.viewcount >= gp.g_p50_view then 'high'
           when qa.viewcount >= gp.g_p20_view then 'medium'
           else 'low'
         end as view_bucket
  from q_activity qa
  cross join global_percentiles gp
), final_rank as (
  select qa.question_id,
         qa.score,
         qa.viewcount,
         qa.time_to_first_answer_sec,
         qb.view_bucket,
         qs.quality_score,
         array_agg(distinct te.tag) as tags,
         dense_rank() over (order by qs.quality_score desc, qa.viewcount desc, qa.score desc) as quality_rank
  from q_activity qa
  join quality_score qs on qs.question_id = qa.question_id
  left join tag_expanded te on te.question_id = qa.question_id
  left join question_buckets qb on qb.question_id = qa.question_id
  group by qa.question_id, qa.score, qa.viewcount, qa.time_to_first_answer_sec, qb.view_bucket, qs.quality_score
)
select
  fr.question_id,
  fr.quality_rank,
  fr.quality_score,
  fr.score as question_score,
  fr.viewcount,
  fr.time_to_first_answer_sec,
  fr.view_bucket,
  fr.tags,
  ts.tag as top_tag,
  ts.questions as tag_questions,
  ts.avg_views as tag_avg_views,
  tq.p90_quality as tag_p90_quality,
  ui.user_id as owner_user_id,
  ui.displayname as owner_display_name,
  ui.reputation as owner_reputation,
  ui.total_q_score,
  ui.total_a_score,
  ui.q_count,
  ui.a_count
from final_rank fr
left join tag_expanded te on te.question_id = fr.question_id
left join top_tags ts on ts.tag = te.tag and ts.rn <= 100
left join tag_quality tq on tq.tag = te.tag
left join posts p on p.id = fr.question_id
left join user_influence ui on ui.user_id = p.owneruserid
where fr.quality_rank <= 1000
order by fr.quality_rank, fr.question_id
limit 1000;