-- {"query": "899.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2983} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           u.upvotes,
           u.downvotes,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''),'//',2)),''), 'unknown') as site_host
    from users u
    where u.creationdate >= (select max(creationdate) - interval '730 days' from users)
),
question_posts as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.closeddate,
           p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select a.id,
           a.parentid as question_id,
           a.owneruserid,
           a.creationdate,
           a.score
    from posts a
    where a.posttypeid = 2
),
user_activity as (
    select ru.user_id,
           count(distinct qp.id) as questions_asked,
           count(distinct ap.id) as answers_posted,
           sum(coalesce(qp.viewcount,0)) as total_q_views,
           sum(case when qp.closeddate is not null then 1 else 0 end) as questions_closed,
           sum(case when ap.score > 0 then 1 else 0 end) as pos_answers,
           sum(case when ap.score < 0 then 1 else 0 end) as neg_answers
    from recent_users ru
    left join question_posts qp on qp.owneruserid = ru.user_id
    left join answer_posts ap on ap.owneruserid = ru.user_id
    group by ru.user_id
),
tag_exploded as (
    select q.id as question_id,
           lower(trim(t)) as tag
    from question_posts q
    cross join lateral unnest(string_to_array(substring(coalesce(q.tags,'<>'), 2, greatest(length(coalesce(q.tags,'<>'))-2,0)), '><')) as t
),
top_tags as (
    select te.tag,
           count(*) as tag_q_count,
           dense_rank() over(order by count(*) desc, tag) as tag_rank
    from tag_exploded te
    group by te.tag
),
accepted_answerers as (
    select q.id as question_id,
           aa.owneruserid as answerer_id,
           aa.id as answer_id,
           aa.score as answer_score,
           qa.creationdate as q_created,
           aa.creationdate as a_created,
           extract(epoch from (aa.creationdate - qa.creationdate)) / 3600.0 as hours_to_answer
    from question_posts qa
    join posts q on q.id = qa.id
    join posts aa on aa.id = qa.acceptedanswerid
),
vote_summaries as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
commenters as (
    select c.postid,
           count(*) as comment_count,
           count(distinct c.userid) as distinct_commenters,
           max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
post_link_dups as (
    select pl.relatedpostid as canonical_id,
           count(*) as dup_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
post_edit_events as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
           count(*) filter (where ph.posthistorytypeid in (10)) as close_votes_events,
           max(ph.creationdate) as last_edit_date
    from posthistory ph
    group by ph.postid
),
user_badge_summary as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           count(*) as total_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
question_metrics as (
    select q.id as question_id,
           q.owneruserid as owner_id,
           q.creationdate,
           q.score,
           q.viewcount,
           q.answercount,
           q.closeddate,
           vt.upvotes,
           vt.downvotes,
           vt.favorites,
           vt.bounty_started,
           vt.bounty_awarded,
           coalesce(cmt.comment_count,0) as comment_count,
           coalesce(cmt.distinct_commenters,0) as distinct_commenters,
           cmt.last_comment_date,
           pe.edit_count,
           pe.close_votes_events,
           pe.last_edit_date,
           coalesce(d.dup_count,0) as duplicate_of_count
    from question_posts q
    left join vote_summaries vt on vt.postid = q.id
    left join commenters cmt on cmt.postid = q.id
    left join post_edit_events pe on pe.postid = q.id
    left join post_link_dups d on d.canonical_id = q.id
),
user_rollup as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate,
           ru.location,
           ru.site_host,
           ua.questions_asked,
           ua.answers_posted,
           ua.total_q_views,
           ua.questions_closed,
           ua.pos_answers,
           ua.neg_answers,
           coalesce(ubs.gold_badges,0) as gold_badges,
           coalesce(ubs.silver_badges,0) as silver_badges,
           coalesce(ubs.bronze_badges,0) as bronze_badges,
           coalesce(ubs.total_badges,0) as total_badges,
           coalesce(ubs.tag_badges,0) as tag_badges
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badge_summary ubs on ubs.userid = ru.user_id
),
recent_hot_questions as (
    select qm.question_id,
           qm.owner_id,
           qm.creationdate,
           qm.viewcount,
           qm.score,
           qm.answercount,
           (coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0)) as net_votes,
           case when qm.favorites is null then 0 else qm.favorites end as favorites,
           case when qm.closeddate is null then 0 else 1 end as is_closed,
           (coalesce(qm.bounty_started,0) + coalesce(qm.bounty_awarded,0)) as bounty_total,
           (coalesce(qm.comment_count,0) + coalesce(qm.distinct_commenters,0)) as comment_impact,
           greatest(coalesce(qm.last_edit_date, qm.creationdate), coalesce(qm.last_comment_date, qm.creationdate)) as last_activity,
           row_number() over (partition by qm.owner_id order by qm.viewcount desc nulls last, qm.score desc, qm.creationdate desc) as rn_by_owner
    from question_metrics qm
    where qm.creationdate >= (select max(creationdate) - interval '180 days' from posts where posttypeid = 1)
),
owner_peer_window as (
    select rhq.*,
           count(*) over (partition by rhq.owner_id) as owner_recent_q_count,
           avg(rhq.viewcount) over (partition by rhq.owner_id) as owner_avg_views,
           percentile_cont(0.9) within group (order by rhq.viewcount) over (partition by rhq.owner_id) as owner_p90_views
    from recent_hot_questions rhq
),
top_tagged_questions as (
    select q.id as question_id,
           min(tt.tag_rank) as best_tag_rank
    from question_posts q
    left join tag_exploded te on te.question_id = q.id
    left join top_tags tt on tt.tag = te.tag
    group by q.id
),
scored_questions as (
    select opw.question_id,
           opw.owner_id,
           opw.viewcount,
           opw.score,
           opw.answercount,
           opw.net_votes,
           opw.favorites,
           opw.is_closed,
           opw.bounty_total,
           opw.comment_impact,
           opw.last_activity,
           opw.owner_recent_q_count,
           opw.owner_avg_views,
           opw.owner_p90_views,
           tqt.best_tag_rank,
           coalesce(1.0 * opw.viewcount / nullif(opw.owner_avg_views,0), 0.0) as view_vs_owner_avg,
           case when opw.viewcount >= coalesce(opw.owner_p90_views,0) then 1 else 0 end as is_owner_top_decile,
           case when coalesce(tqt.best_tag_rank, 999999) <= 50 then 1 else 0 end as is_in_top50_tag
    from owner_peer_window opw
    left join top_tagged_questions tqt on tqt.question_id = opw.question_id
),
ranked_questions as (
    select sq.*,
           dense_rank() over (order by
               (0.4 * ln(1 + sq.viewcount)
                + 0.25 * ln(1 + greatest(sq.score,0))
                + 0.15 * ln(1 + greatest(sq.net_votes,0))
                + 0.10 * ln(1 + sq.comment_impact)
                + 0.05 * ln(1 + sq.bounty_total)
                + 0.05 * (case when sq.is_closed = 0 then 1 else 0 end)
                + 0.05 * sq.view_vs_owner_avg
                + 0.05 * sq.is_owner_top_decile
                + 0.05 * sq.is_in_top50_tag
               ) desc,
               sq.last_activity desc,
               sq.question_id
           ) as popularity_rank
    from scored_questions sq
),
user_question_join as (
    select rq.question_id,
           rq.owner_id,
           rq.popularity_rank,
           rq.last_activity,
           rq.viewcount,
           rq.score,
           rq.answercount,
           rq.net_votes,
           rq.favorites,
           rq.is_closed,
           rq.is_owner_top_decile,
           rq.is_in_top50_tag,
           ur.displayname,
           ur.reputation,
           ur.location,
           ur.questions_asked,
           ur.answers_posted,
           ur.total_q_views,
           ur.questions_closed,
           ur.gold_badges,
           ur.silver_badges,
           ur.bronze_badges,
           ur.site_host
    from ranked_questions rq
    left join user_rollup ur on ur.user_id = rq.owner_id
),
dup_collisions as (
    select q.question_id,
           sum(case when ph.posthistorytypeid = 10 and ph.comment::varchar ~ '(^|[^0-9])101([^0-9]|$)' then 1 else 0 end) as duplicate_closes,
           max(ph.creationdate) as last_close_event
    from question_posts qp
    join posts q on q.id = qp.id
    left join posthistory ph on ph.postid = qp.id and ph.posthistorytypeid in (10,11)
    group by q.question_id
),
final_candidates as (
    select uqj.*,
           coalesce(dc.duplicate_closes,0) as duplicate_closes,
           dc.last_close_event,
           aa.answer_id,
           aa.answerer_id,
           aa.answer_score,
           aa.hours_to_answer
    from user_question_join uqj
    left join dup_collisions dc on dc.question_id = uqj.question_id
    left join accepted_answerers aa on aa.question_id = uqj.question_id
),
normed as (
    select fc.*,
           ntile(100) over (order by fc.popularity_rank asc) as popularity_percentile,
           sum(case when fc.is_closed = 1 then 1 else 0 end) over (partition by fc.owner_id) as owner_closed_qs,
           count(*) over (partition by fc.owner_id) as owner_total_qs
    from final_candidates fc
)
select *
from (
    select n.*,
           case
               when n.reputation >= 100000 then 'legend'
               when n.reputation >= 10000 then 'expert'
               when n.reputation >= 1000 then 'intermediate'
               else 'novice'
           end as rep_tier,
           case when coalesce(n.owner_closed_qs,0) > greatest(1, coalesce(n.owner_total_qs,0))/3 then 1 else 0 end as owner_often_closed_flag
    from normed n
) z
where (z.popularity_percentile <= 10 or (z.viewcount >= 1000 and z.net_votes >= 10))
  and coalesce(z.location,'') not ilike '%test%'
  and (z.site_host is null or z.site_host not ilike '%localhost%')
  and (z.duplicate_closes = 0 or z.is_in_top50_tag = 1)
order by z.popularity_rank asc, z.last_activity desc
limit 500;