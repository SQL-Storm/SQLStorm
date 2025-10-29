-- {"query": "389.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3676}
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         u.websiteurl,
         u.upvotes,
         u.downvotes,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_stats as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
         min(b.date) as first_badge_date,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
questions_cte as (
  select p.id as question_id,
         p.owneruserid as asker_id,
         p.creationdate as q_created,
         p.score as q_score,
         p.viewcount,
         p.answercount,
         p.favoritecount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.closeddate,
         p.communityowneddate,
         p.contentlicense
  from posts p
  where p.posttypeid = 1
),
answers_cte as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.creationdate as a_created,
         a.score as a_score
  from posts a
  where a.posttypeid = 2
),
first_answer_per_question as (
  select a.question_id,
         a.answer_id,
         a.answerer_id,
         a.a_created,
         a.a_score,
         row_number() over (partition by a.question_id order by a.a_created asc, a.answer_id) as rn
  from answers_cte a
),
accepted_vs_first as (
  select q.question_id,
         q.asker_id,
         q.q_created,
         q.q_score,
         q.viewcount,
         q.answercount,
         q.favoritecount,
         q.title,
         q.tags,
         q.acceptedanswerid,
         fa.answer_id as first_answer_id,
         fa.answerer_id as first_answerer_id,
         fa.a_created as first_answer_created,
         fa.a_score as first_answer_score,
         case when q.acceptedanswerid is not null and q.acceptedanswerid = fa.answer_id then 1 else 0 end as first_is_accepted
  from questions_cte q
  left join first_answer_per_question fa
    on fa.question_id = q.question_id
   and fa.rn = 1
),
user_post_activity as (
  select u.id as user_id,
         count(*) filter (where p.posttypeid = 1) as q_count,
         count(*) filter (where p.posttypeid = 2) as a_count,
         sum(p.score) filter (where p.posttypeid = 1) as q_score_sum,
         sum(p.score) filter (where p.posttypeid = 2) as a_score_sum,
         max(p.lastactivitydate) as last_activity
  from users u
  left join posts p
    on p.owneruserid = u.id
  group by u.id
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
         count(*) filter (where v.votetypeid in (10,11,12)) as mod_votes
  from votes v
  group by v.postid
),
linked_duplicates as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as orig_post_id,
         pl.creationdate as link_created
  from postlinks pl
  where pl.linktypeid = 3
),
close_events as (
  select ph.postid,
         ph.creationdate as closed_at,
         case when nullif(ph.comment, '') is null then null else cast(nullif(ph.comment, '') as integer) end as close_reason_id,
         cr.name as close_reason_name
  from posthistory ph
  left join closereasontypes cr
    on cr.id = case when nullif(ph.comment, '') is null then null else cast(nullif(ph.comment, '') as integer) end
  where ph.posthistorytypeid = 10
),
question_enriched as (
  select avf.*,
         qph.closed_at,
         qph.close_reason_id,
         qph.close_reason_name,
         vd.upvotes as q_upvotes,
         vd.downvotes as q_downvotes,
         vd.bounty_started as q_bounty_started,
         vd.bounty_awarded as q_bounty_awarded,
         vd.mod_votes as q_mod_votes,
         ld.orig_post_id as duplicate_of_id,
         coalesce(ld.orig_post_id, 0) as dup_of_id_coalesce
  from accepted_vs_first avf
  left join votes_agg vd on vd.postid = avf.question_id
  left join close_events qph on qph.postid = avf.question_id
  left join linked_duplicates ld on ld.dup_post_id = avf.question_id
),
answer_enriched as (
  select a.answer_id,
         a.question_id,
         a.answerer_id,
         a.a_created,
         a.a_score,
         coalesce(va.upvotes,0) as a_upvotes,
         coalesce(va.downvotes,0) as a_downvotes,
         coalesce(va.bounty_started,0) as a_bounty_started,
         coalesce(va.bounty_awarded,0) as a_bounty_awarded
  from answers_cte a
  left join votes_agg va on va.postid = a.answer_id
),
tag_expanded as (
  select q.question_id,
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from question_enriched q
  where q.tags is not null
),
tag_rank as (
  select te.question_id,
         te.tag,
         dense_rank() over (partition by te.question_id order by te.tag) as tag_rank
  from tag_expanded te
),
question_tag_pivot as (
  select tr.question_id,
         max(case when tr.tag_rank = 1 then tr.tag end) as tag1,
         max(case when tr.tag_rank = 2 then tr.tag end) as tag2,
         max(case when tr.tag_rank = 3 then tr.tag end) as tag3
  from tag_rank tr
  group by tr.question_id
),
user_quality as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.norm_location,
         coalesce(ubs.total_badges,0) as total_badges,
         coalesce(ubs.gold_badges,0) as gold_badges,
         coalesce(ubs.silver_badges,0) as silver_badges,
         coalesce(ubs.bronze_badges,0) as bronze_badges,
         coalesce(upa.q_count,0) as q_count,
         coalesce(upa.a_count,0) as a_count,
         coalesce(upa.q_score_sum,0) as q_score_sum,
         coalesce(upa.a_score_sum,0) as a_score_sum,
         upa.last_activity,
         case
           when coalesce(upa.a_count,0) = 0 then null
           else round(coalesce(upa.a_score_sum,0) / nullif(upa.a_count,0), 3)
         end as avg_answer_score,
         case
           when coalesce(upa.q_count,0) = 0 then null
           else round(coalesce(upa.q_score_sum,0) / nullif(upa.q_count,0), 3)
         end as avg_question_score
  from recent_users ru
  left join user_badge_stats ubs on ubs.userid = ru.user_id
  left join user_post_activity upa on upa.user_id = ru.user_id
),
question_answer_gap as (
  select qe.question_id,
         qe.asker_id,
         qe.q_created,
         qe.q_score,
         qe.viewcount,
         qe.answercount,
         qe.favoritecount,
         qe.title,
         qtp.tag1, qtp.tag2, qtp.tag3,
         qe.acceptedanswerid,
         qe.first_answer_id,
         qe.first_answerer_id,
         qe.first_answer_created,
         qe.first_answer_score,
         qe.first_is_accepted,
         extract(epoch from (qe.first_answer_created - qe.q_created)) as seconds_to_first_answer,
         extract(epoch from (qe.closed_at - qe.q_created)) as seconds_to_close,
         qe.closed_at,
         qe.close_reason_id,
         qe.close_reason_name,
         qe.q_upvotes,
         qe.q_downvotes,
         qe.q_bounty_started,
         qe.q_bounty_awarded,
         qe.q_mod_votes,
         qe.duplicate_of_id
  from question_enriched qe
  left join question_tag_pivot qtp on qtp.question_id = qe.question_id
),
dup_orig_enriched as (
  select ld.dup_post_id,
         ld.orig_post_id,
         qp.q_score as orig_q_score,
         qp.viewcount as orig_views,
         qp.answercount as orig_answercount
  from linked_duplicates ld
  left join questions_cte qp on qp.question_id = ld.orig_post_id
),
activity_window as (
  select qa.asker_id,
         qa.question_id,
         qa.q_created,
         count(*) over (partition by qa.asker_id order by qa.q_created rows between unbounded preceding and current row) as asker_q_running_count,
         avg(qa.q_score) over (partition by qa.asker_id order by qa.q_created rows between 10 preceding and current row) as asker_q_last11_avg_score,
         sum(qa.viewcount) over (partition by qa.asker_id order by qa.q_created rows between 10 preceding and current row) as asker_q_last11_views
  from question_answer_gap qa
),
best_answer_per_user as (
  select ae.answerer_id,
         ae.answer_id,
         ae.a_score,
         row_number() over (partition by ae.answerer_id order by ae.a_score desc nulls last, ae.a_created asc) as rn
  from answer_enriched ae
),
question_comment_sentiment as (
  select c.postid as question_id,
         sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_mentions,
         sum(case when position('why' in lower(c.text)) > 0 then 1 else 0 end) as why_mentions,
         sum(case when position('?' in c.text) > 0 then 1 else 0 end) as question_marks,
         max(length(c.text)) as max_comment_len
  from comments c
  join posts p on p.id = c.postid and p.posttypeid = 1
  group by c.postid
),
combined as (
  select qa.question_id,
         qa.asker_id,
         uqa.displayname as asker_name,
         uq.reputation as asker_reputation,
         uq.total_badges as asker_total_badges,
         uq.gold_badges as asker_gold_badges,
         uq.avg_question_score,
         qa.q_created,
         qa.q_score,
         qa.viewcount,
         qa.answercount,
         qa.favoritecount,
         qa.title,
         coalesce(qa.tag1,'') as tag1,
         coalesce(qa.tag2,'') as tag2,
         coalesce(qa.tag3,'') as tag3,
         qa.acceptedanswerid,
         qa.first_answer_id,
         qa.first_answerer_id,
         ua.displayname as first_answerer_name,
         ua.reputation as first_answerer_reputation,
         qa.first_answer_created,
         qa.first_answer_score,
         qa.first_is_accepted,
         qa.seconds_to_first_answer,
         qa.seconds_to_close,
         qa.closed_at,
         qa.close_reason_name,
         qa.q_upvotes,
         qa.q_downvotes,
         qa.q_bounty_started,
         qa.q_bounty_awarded,
         qa.q_mod_votes,
         qa.duplicate_of_id,
         dof.orig_q_score,
         dof.orig_views,
         dof.orig_answercount,
         aw.asker_q_running_count,
         aw.asker_q_last11_avg_score,
         aw.asker_q_last11_views,
         qcs.thanks_mentions,
         qcs.why_mentions,
         qcs.question_marks,
         qcs.max_comment_len,
         case
           when qa.answercount = 0 then 'Unanswered'
           when qa.acceptedanswerid is not null then 'HasAccepted'
           when qa.closed_at is not null then 'ClosedNoAccept'
           when qa.duplicate_of_id is not null then 'Duplicate'
           else 'AnsweredNoAccept'
         end as question_status
  from question_answer_gap qa
  left join users uqa on uqa.id = qa.asker_id
  left join user_quality uq on uq.user_id = qa.asker_id
  left join users ua on ua.id = qa.first_answerer_id
  left join dup_orig_enriched dof on dof.dup_post_id = qa.question_id
  left join activity_window aw on aw.question_id = qa.question_id
  left join question_comment_sentiment qcs on qcs.question_id = qa.question_id
),
scored as (
  select c.*,
         coalesce(c.q_upvotes - c.q_downvotes, 0) as net_votes,
         case
           when c.seconds_to_first_answer is null then 0
           when c.seconds_to_first_answer <= 600 then 5
           when c.seconds_to_first_answer <= 3600 then 3
           when c.seconds_to_first_answer <= 86400 then 1
           else 0
         end as speed_bucket,
         case when c.first_is_accepted = 1 then 3 else 0 end as acceptance_bonus,
         case when c.close_reason_name is not null then -2 else 0 end as closed_penalty,
         case when c.question_status = 'Duplicate' then -1 else 0 end as duplicate_penalty,
         greatest(0, least(5, coalesce(c.q_score,0))) as base_quality,
         coalesce(nullif(length(c.title),0), 0) as title_len,
         coalesce(length(c.tag1) + length(c.tag2) + length(c.tag3), 0) as tags_len_sum
  from combined c
),
final_rank as (
  select s.*,
         (
           0.4 * base_quality +
           0.2 * speed_bucket +
           0.3 * greatest(0, net_votes) +
           0.1 * acceptance_bonus +
           closed_penalty + duplicate_penalty +
           least(2, coalesce(s.asker_total_badges,0) / 10.0)
         ) as perf_score,
         row_number() over (
           partition by coalesce(s.tag1,'(none)')
           order by (
             0.4 * base_quality +
             0.2 * speed_bucket +
             0.3 * greatest(0, net_votes) +
             0.1 * acceptance_bonus +
             closed_penalty + duplicate_penalty +
             least(2, coalesce(s.asker_total_badges,0) / 10.0)
           ) desc,
           s.q_created desc,
           s.question_id
         ) as tag_rank
  from scored s
)
select
  fr.question_id,
  fr.title,
  fr.tag1, fr.tag2, fr.tag3,
  fr.question_status,
  fr.q_created,
  fr.asker_id,
  fr.asker_name,
  fr.asker_reputation,
  fr.asker_total_badges,
  fr.viewcount,
  fr.q_score,
  fr.net_votes,
  fr.answercount,
  fr.seconds_to_first_answer,
  fr.first_is_accepted,
  fr.closed_at,
  fr.close_reason_name,
  fr.duplicate_of_id,
  fr.perf_score,
  fr.tag_rank,
  fr.thanks_mentions,
  fr.why_mentions,
  fr.max_comment_len
from final_rank fr
where (
    fr.tag1 is not null
    or fr.tag2 is not null
    or fr.tag3 is not null
)
and coalesce(fr.q_created, cast('2024-10-01 12:34:56' as timestamp)) >= (cast('2024-10-01 12:34:56' as timestamp) - interval '730 days')
and (
    fr.perf_score > 2
    or (fr.answercount = 0 and fr.viewcount > 100)
    or (fr.close_reason_name is null and fr.net_votes >= 0)
)
order by fr.perf_score desc, fr.q_created desc
limit 500;