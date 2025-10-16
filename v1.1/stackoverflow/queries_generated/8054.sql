-- {"query": "8054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3484} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         u.websiteurl,
         row_number() over (order by u.creationdate desc) as rn
  from users u
),
top_users as (
  select ru.*
  from recent_users ru
  where ru.rn <= 500
),
user_posts as (
  select p.id,
         p.posttypeid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.parentid,
         p.lastactivitydate,
         p.commentcount,
         p.answercount
  from posts p
  join top_users tu on tu.user_id = p.owneruserid
  where p.creationdate >= (select min(creationdate) from top_users)
),
q_and_a as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as q_created,
    q.score as q_score,
    q.viewcount as q_views,
    q.title as q_title,
    q.tags as q_tags,
    q.answercount,
    a.id as answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as a_created,
    a.score as a_score,
    a.commentcount as a_commentcount,
    case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted
  from user_posts q
  left join posts a
    on a.parentid = q.id
   and a.posttypeid = 2
  where q.posttypeid = 1
),
vote_summaries as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  group by v.postid
),
commenters as (
  select c.postid,
         count(*) as comment_count,
         count(distinct coalesce(c.userid, -c.id)) as distinct_commenters
  from comments c
  group by c.postid
),
link_dupes as (
  select pl.postid,
         count(*) filter (where pl.linktypeid = 3) as dup_count,
         count(*) filter (where pl.linktypeid = 1) as link_count
  from postlinks pl
  group by pl.postid
),
post_edits as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
  from posthistory ph
  group by ph.postid
),
user_badges as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as golds,
         sum(case when b.class = 2 then 1 else 0 end) as silvers,
         sum(case when b.class = 3 then 1 else 0 end) as bronzes,
         sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
         count(*) as total_badges,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
tag_explode as (
  select
    qa.question_id,
    unnest(string_to_array(substring(qa.q_tags, 2, greatest(length(qa.q_tags)-2,0)), '><')) as tag
  from q_and_a qa
  where qa.q_tags is not null
),
tag_rank as (
  select te.question_id,
         te.tag,
         dense_rank() over (partition by te.question_id order by count(*) desc, te.tag) as tag_rank
  from tag_explode te
  group by te.question_id, te.tag
),
accepted_answer_latency as (
  select
    qa.question_id,
    min(extract(epoch from (qa.a_created - qa.q_created))) filter (where qa.is_accepted = 1) as accepted_latency_seconds,
    min(extract(epoch from (qa.a_created - qa.q_created))) as first_answer_latency_seconds,
    count(*) as total_answers,
    count(*) filter (where qa.is_accepted = 1) as accepted_answers
  from q_and_a qa
  group by qa.question_id
),
question_quality as (
  select
    qa.question_id,
    qa.q_score,
    qa.q_views,
    vs.upvotes as q_up,
    vs.downvotes as q_down,
    coalesce(vs.favorites, 0) as q_favs,
    coalesce(vs.bounty_total, 0) as bounty_total,
    coalesce(cmt.comment_count, 0) as q_comments,
    coalesce(cmt.distinct_commenters, 0) as q_commenters,
    coalesce(ld.dup_count, 0) as dup_links,
    coalesce(ld.link_count, 0) as out_links,
    coalesce(pe.edit_events, 0) as edit_events,
    pe.last_edit_at,
    coalesce(pe.close_events, 0) as close_events,
    pe.last_close_reason_id
  from (select distinct question_id, q_score, q_views from q_and_a) qa
  left join vote_summaries vs on vs.postid = qa.question_id
  left join commenters cmt on cmt.postid = qa.question_id
  left join link_dupes ld on ld.postid = qa.question_id
  left join post_edits pe on pe.postid = qa.question_id
),
user_activity as (
  select
    tu.user_id,
    count(*) filter (where up.posttypeid = 1) as questions_authored,
    count(*) filter (where up.posttypeid = 2) as answers_authored,
    sum(coalesce(up.score,0)) as total_post_score,
    sum(coalesce(up.viewcount,0)) as total_views,
    max(up.lastactivitydate) as last_post_activity,
    min(up.creationdate) as first_post_at
  from top_users tu
  left join user_posts up on up.owneruserid = tu.user_id
  group by tu.user_id
),
answer_engagement as (
  select
    qa.answer_id,
    qa.answerer_id,
    qa.question_id,
    qa.a_score,
    qa.is_accepted,
    vs.upvotes as a_up,
    vs.downvotes as a_down,
    coalesce(cmt.comment_count, 0) as a_comments
  from q_and_a qa
  left join vote_summaries vs on vs.postid = qa.answer_id
  left join commenters cmt on cmt.postid = qa.answer_id
),
user_answer_stats as (
  select
    ae.answerer_id as user_id,
    count(*) as answers_count,
    sum(case when ae.is_accepted = 1 then 1 else 0 end) as accepted_count,
    avg(ae.a_score) as avg_answer_score,
    percentile_cont(0.5) within group (order by ae.a_score) as median_answer_score,
    sum(ae.a_up) as total_answer_up,
    sum(ae.a_down) as total_answer_down,
    sum(ae.a_comments) as total_answer_comments
  from answer_engagement ae
  group by ae.answerer_id
),
question_owner as (
  select q.owneruserid as asker_id, q.id as question_id
  from posts q
  where q.posttypeid = 1
),
cross_user_interactions as (
  select
    ae.answer_id,
    ae.question_id,
    qo.asker_id,
    ae.answerer_id,
    case when ae.answerer_id = qo.asker_id then 1 else 0 end as self_answer
  from answer_engagement ae
  join question_owner qo on qo.question_id = ae.question_id
),
user_pair_stats as (
  select
    ci.asker_id,
    ci.answerer_id,
    count(*) as answers_between_pair,
    sum(ci.self_answer) as self_answers
  from cross_user_interactions ci
  group by ci.asker_id, ci.answerer_id
),
final_users as (
  select
    tu.user_id,
    tu.displayname,
    tu.reputation,
    tu.location,
    tu.websiteurl,
    ua.questions_authored,
    ua.answers_authored,
    ua.total_post_score,
    ua.total_views,
    ua.last_post_activity,
    ua.first_post_at,
    ub.golds,
    ub.silvers,
    ub.bronzes,
    ub.tag_badges,
    ub.total_badges,
    ub.last_badge_at,
    uas.answers_count,
    uas.accepted_count,
    uas.avg_answer_score,
    uas.median_answer_score,
    uas.total_answer_up,
    uas.total_answer_down,
    uas.total_answer_comments
  from top_users tu
  left join user_activity ua on ua.user_id = tu.user_id
  left join user_badges ub on ub.userid = tu.user_id
  left join user_answer_stats uas on uas.user_id = tu.user_id
),
question_enriched as (
  select
    qq.question_id,
    qq.q_score,
    qq.q_views,
    qq.q_up,
    qq.q_down,
    qq.q_favs,
    qq.bounty_total,
    qq.q_comments,
    qq.q_commenters,
    qq.dup_links,
    qq.out_links,
    qq.edit_events,
    qq.last_edit_at,
    qq.close_events,
    qq.last_close_reason_id,
    aal.accepted_latency_seconds,
    aal.first_answer_latency_seconds,
    aal.total_answers,
    aal.accepted_answers,
    min(tr.tag) filter (where tr.tag_rank = 1) as primary_tag
  from question_quality qq
  left join accepted_answer_latency aal on aal.question_id = qq.question_id
  left join tag_rank tr on tr.question_id = qq.question_id
  group by
    qq.question_id, qq.q_score, qq.q_views, qq.q_up, qq.q_down, qq.q_favs, qq.bounty_total,
    qq.q_comments, qq.q_commenters, qq.dup_links, qq.out_links, qq.edit_events, qq.last_edit_at,
    qq.close_events, qq.last_close_reason_id, aal.accepted_latency_seconds, aal.first_answer_latency_seconds,
    aal.total_answers, aal.accepted_answers
),
score_buckets as (
  select
    qe.question_id,
    case
      when coalesce(qe.q_score,0) >= 50 then '50+'
      when coalesce(qe.q_score,0) >= 20 then '20-49'
      when coalesce(qe.q_score,0) >= 10 then '10-19'
      when coalesce(qe.q_score,0) >= 0  then '0-9'
      when coalesce(qe.q_score,0) >= -5 then '-5 to -1'
      else '< -5'
    end as score_bucket
  from question_enriched qe
),
null_safety as (
  select
    fu.*,
    coalesce(fu.questions_authored,0) as nn_questions_authored,
    coalesce(fu.answers_authored,0) as nn_answers_authored,
    coalesce(fu.total_post_score,0) as nn_total_post_score
  from final_users fu
),
aggregate_by_tag as (
  select
    qe.primary_tag,
    count(*) as questions,
    avg(qe.q_views) as avg_views,
    avg(qe.q_score) as avg_qscore,
    avg(qe.total_answers) as avg_answers,
    avg(coalesce(qe.accepted_latency_seconds, qe.first_answer_latency_seconds)) as avg_time_to_resolution_sec
  from question_enriched qe
  group by qe.primary_tag
),
pair_summary as (
  select
    ups.asker_id,
    sum(ups.answers_between_pair) as total_answers_received_from_pairs,
    sum(ups.self_answers) as total_self_answers
  from user_pair_stats ups
  group by ups.asker_id
)
select
  fu.user_id,
  fu.displayname,
  fu.reputation,
  fu.location,
  fu.websiteurl,
  fu.nn_questions_authored as questions_authored,
  fu.nn_answers_authored as answers_authored,
  fu.nn_total_post_score as total_post_score,
  fu.total_views,
  fu.golds,
  fu.silvers,
  fu.bronzes,
  fu.tag_badges,
  fu.total_badges,
  fu.last_badge_at,
  fu.last_post_activity,
  fu.first_post_at,
  coalesce(ps.total_answers_received_from_pairs, 0) as answers_from_others,
  coalesce(ps.total_self_answers, 0) as self_answers,
  sum(case when qa.is_accepted = 1 then 1 else 0 end) as accepted_answers_by_user,
  avg(ae.a_score) as avg_answer_score_userwide,
  sum(vs.upvotes) filter (where qa.answer_id is not null) as total_up_on_answers,
  sum(vs.downvotes) filter (where qa.answer_id is not null) as total_down_on_answers,
  count(distinct qe.question_id) as distinct_questions_touched,
  count(distinct qe.primary_tag) as distinct_primary_tags,
  min(qe.last_edit_at) as earliest_edit_seen,
  max(qe.last_edit_at) as latest_edit_seen,
  percentile_cont(0.5) within group (order by coalesce(qe.q_views,0)) as median_views_on_seen_questions,
  percentile_cont(0.9) within group (order by coalesce(qe.q_score,0)) as p90_qscore_on_seen_questions,
  string_agg(distinct sb.score_bucket, ', ' order by sb.score_bucket) as seen_score_buckets,
  coalesce(at.questions, 0) as sample_tag_questions,
  coalesce(at.avg_views, 0) as sample_tag_avg_views,
  coalesce(at.avg_qscore, 0) as sample_tag_avg_qscore,
  coalesce(at.avg_answers, 0) as sample_tag_avg_answers,
  coalesce(at.avg_time_to_resolution_sec, 0) as sample_tag_avg_time_to_resolution_sec
from null_safety fu
left join q_and_a qa on qa.answerer_id = fu.user_id
left join answer_engagement ae on ae.answer_id = qa.answer_id
left join vote_summaries vs on vs.postid = qa.answer_id
left join question_enriched qe on qe.question_id = qa.question_id
left join score_buckets sb on sb.question_id = qe.question_id
left join pair_summary ps on ps.asker_id = fu.user_id
left join aggregate_by_tag at
  on at.primary_tag = (
    select tr2.tag
    from tag_rank tr2
    where tr2.question_id = qa.question_id
    order by tr2.tag_rank
    limit 1
  )
group by
  fu.user_id, fu.displayname, fu.reputation, fu.location, fu.websiteurl,
  fu.nn_questions_authored, fu.nn_answers_authored, fu.nn_total_post_score, fu.total_views,
  fu.golds, fu.silvers, fu.bronzes, fu.tag_badges, fu.total_badges, fu.last_badge_at,
  fu.last_post_activity, fu.first_post_at,
  ps.total_answers_received_from_pairs, ps.total_self_answers,
  at.questions, at.avg_views, at.avg_qscore, at.avg_answers, at.avg_time_to_resolution_sec
order by
  coalesce(fu.nn_total_post_score,0) desc,
  coalesce(fu.answers_authored,0) desc,
  fu.reputation desc
limit 200;