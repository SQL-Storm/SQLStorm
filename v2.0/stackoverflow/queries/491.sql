with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.location,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
           date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_badge_rollup as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
           sum(coalesce(p.score,0)) filter (where p.posttypeid = 1) as question_score,
           avg(nullif(p.answercount,0)) filter (where p.posttypeid = 1) as avg_answers_per_question,
           count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted_questions,
           count(distinct p.id) filter (where p.posttypeid = 1 and p.closeddate is not null) as closed_questions
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
answer_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 2) as answers,
           sum(coalesce(p.score,0)) filter (where p.posttypeid = 2) as answer_score,
           count(*) filter (where p.posttypeid = 2 and p.score > 0) as upvoted_answers,
           count(*) filter (where p.posttypeid = 2 and p.score < 0) as downvoted_answers
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_activity as (
    select c.userid as user_id,
           count(*) as comments,
           sum(coalesce(c.score,0)) as comment_score,
           max(c.creationdate) as last_comment_at
    from comments c
    where c.userid is not null
    group by c.userid
),
dup_close_events as (
    select ph.postid,
           min(ph.creationdate) as first_dup_close_at,
           count(*) as dup_close_votes
    from posthistory ph
    where ph.posthistorytypeid in (10)
      and ph.comment in ('1','101')
    group by ph.postid
),
linkage as (
    select pl.relatedpostid as canonical_id,
           count(*) filter (where pl.linktypeid = 3) as duplicates_pointing_here,
           count(*) filter (where pl.linktypeid = 1) as linked_here
    from postlinks pl
    group by pl.relatedpostid
),
tag_explosion as (
    select p.id as post_id,
           unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag_name
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
top_tags as (
    select te.tag_name,
           count(*) as tag_q_count,
           percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_q_score
    from tag_explosion te
    join posts p on p.id = te.post_id
    group by te.tag_name
    having count(*) > 50
),
user_primary_tag as (
    select p.owneruserid as user_id,
           te.tag_name,
           count(*) as q_count,
           row_number() over (partition by p.owneruserid order by count(*) desc, min(p.creationdate)) as rn
    from posts p
    join tag_explosion te on te.post_id = p.id
    where p.posttypeid = 1
    group by p.owneruserid, te.tag_name
),
vote_summaries as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounties_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounties_awarded
    from votes v
    group by v.postid
),
post_quality as (
    select p.id,
           p.posttypeid,
           p.owneruserid as user_id,
           coalesce(vs.upvotes,0) - coalesce(vs.downvotes,0) as net_votes,
           coalesce(p.score,0) as score,
           coalesce(vs.bounties_awarded,0) as bounty_awarded,
           coalesce(vs.bounties_started,0) as bounty_started,
           (coalesce(vs.upvotes,0) + coalesce(vs.downvotes,0)) as total_votes,
           case
             when p.posttypeid = 1 then coalesce(p.viewcount,0)
             else null
           end as views_if_question
    from posts p
    left join vote_summaries vs on vs.postid = p.id
),
user_quality as (
    select pq.user_id,
           sum(case when pq.posttypeid = 1 then pq.net_votes else 0 end) as q_net_votes,
           sum(case when pq.posttypeid = 2 then pq.net_votes else 0 end) as a_net_votes,
           sum(pq.bounty_awarded) as bounty_gained,
           sum(pq.bounty_started) as bounty_put_up,
           avg(nullif(pq.total_votes,0)) as avg_votes_per_post,
           percentile_disc(0.9) within group (order by coalesce(pq.views_if_question,0)) as p90_question_views
    from post_quality pq
    where pq.user_id is not null
    group by pq.user_id
),
accepted_answerers as (
    select a.owneruserid as user_id,
           count(*) as accepted_answers
    from posts q
    join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
      and q.acceptedanswerid = a.id
    group by a.owneruserid
),
recent_hot_bumps as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid = 50) as community_bumps,
           count(*) filter (where ph.posthistorytypeid = 52) as hot_selected,
           count(*) filter (where ph.posthistorytypeid = 53) as hot_removed,
           max(ph.creationdate) as last_activity_event
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by ph.postid
),
post_closure_summary as (
    select q.owneruserid as user_id,
           count(*) as total_closed_questions,
           min(dce.first_dup_close_at) as first_closed_at,
           avg(dce.dup_close_votes) as avg_dup_close_votes
    from posts q
    join dup_close_events dce on dce.postid = q.id
    where q.posttypeid = 1
    group by q.owneruserid
),
user_post_counts as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as total_questions,
           count(*) filter (where p.posttypeid = 2) as total_answers,
           count(*) filter (where p.posttypeid not in (1,2) or p.posttypeid is null) as other_posts
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
cohort_rank as (
    select ru.user_id,
           ru.cohort_month,
           dense_rank() over (partition by ru.cohort_month order by coalesce(uq.a_net_votes,0) + coalesce(uq.q_net_votes,0) desc) as perf_rank_in_cohort
    from recent_users ru
    left join user_quality uq on uq.user_id = ru.user_id
),
active_linked_questions as (
    select q.owneruserid as user_id,
           count(distinct q.id) as linked_questions,
           count(distinct case when rl.hot_selected > 0 then q.id end) as hot_linked_questions
    from posts q
    left join linkage l on l.canonical_id = q.id
    left join recent_hot_bumps rl on rl.postid = q.id
    where q.posttypeid = 1
      and coalesce(l.duplicates_pointing_here,0) + coalesce(l.linked_here,0) > 0
    group by q.owneruserid
),
final_users as (
    select ru.user_id,
           ru.displayname,
           ru.location,
           ru.website_host,
           ru.reputation,
           ru.cohort_month,
           coalesce(ubr.total_badges,0) as total_badges,
           coalesce(ubr.gold_badges,0) as gold_badges,
           coalesce(ubr.silver_badges,0) as silver_badges,
           coalesce(ubr.bronze_badges,0) as bronze_badges,
           ubr.last_badge_date,
           coalesce(qa.questions,0) as questions,
           coalesce(qa.question_views,0) as question_views,
           coalesce(qa.question_score,0) as question_score,
           coalesce(qa.avg_answers_per_question,0) as avg_answers_per_question,
           coalesce(qa.accepted_questions,0) as accepted_questions,
           coalesce(qa.closed_questions,0) as closed_questions,
           coalesce(aa.answers,0) as answers,
           coalesce(aa.answer_score,0) as answer_score,
           coalesce(aa.upvoted_answers,0) as upvoted_answers,
           coalesce(aa.downvoted_answers,0) as downvoted_answers,
           coalesce(ca.comments,0) as comments,
           coalesce(ca.comment_score,0) as comment_score,
           ca.last_comment_at,
           coalesce(uq.q_net_votes,0) as q_net_votes,
           coalesce(uq.a_net_votes,0) as a_net_votes,
           coalesce(uq.bounty_gained,0) as bounty_gained,
           coalesce(uq.bounty_put_up,0) as bounty_put_up,
           coalesce(uq.avg_votes_per_post,0) as avg_votes_per_post,
           coalesce(uq.p90_question_views,0) as p90_question_views,
           coalesce(aa2.accepted_answers,0) as accepted_answers,
           coalesce(pcs.total_closed_questions,0) as total_closed_questions,
           pcs.first_closed_at,
           pcs.avg_dup_close_votes,
           coalesce(upc.total_questions,0) as total_questions_lifetime,
           coalesce(upc.total_answers,0) as total_answers_lifetime,
           coalesce(alq.linked_questions,0) as linked_questions,
           coalesce(alq.hot_linked_questions,0) as hot_linked_questions
    from recent_users ru
    left join user_badge_rollup ubr on ubr.userid = ru.user_id
    left join question_activity qa on qa.user_id = ru.user_id
    left join answer_activity aa on aa.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join accepted_answerers aa2 on aa2.user_id = ru.user_id
    left join post_closure_summary pcs on pcs.user_id = ru.user_id
    left join user_post_counts upc on upc.user_id = ru.user_id
    left join active_linked_questions alq on alq.user_id = ru.user_id
),
scored as (
    select fu.*,
           coalesce(fu.a_net_votes,0) * 2
             + coalesce(fu.q_net_votes,0) * 1.5
             + coalesce(fu.accepted_answers,0) * 5
             + coalesce(fu.questions,0) * 0.2
             + coalesce(fu.answers,0) * 0.5
             + coalesce(fu.total_badges,0) * 0.3
             + least(coalesce(fu.p90_question_views,0) / 1000.0, 50) as performance_score,
           case
             when fu.gold_badges >= 1 and fu.accepted_answers >= 10 then 'elite'
             when fu.reputation >= 10000 then 'veteran'
             when fu.answers >= 50 then 'prolific'
             when fu.questions >= 50 then 'curious'
             else 'rising'
           end as segment_label
    from final_users fu
),
with_primary_tag as (
    select s.*,
           upt.tag_name as primary_tag,
           tt.median_q_score as primary_tag_median_q_score
    from scored s
    left join user_primary_tag upt
      on upt.user_id = s.user_id
     and upt.rn = 1
    left join top_tags tt
      on tt.tag_name = upt.tag_name
),
ranked as (
    select wpt.*,
           cr.perf_rank_in_cohort,
           row_number() over (
             partition by wpt.segment_label
             order by wpt.performance_score desc, wpt.reputation desc, wpt.user_id
           ) as segment_rank,
           rank() over (order by wpt.performance_score desc nulls last) as global_rank
    from with_primary_tag wpt
    left join cohort_rank cr on cr.user_id = wpt.user_id
)
select
    r.user_id,
    r.displayname,
    coalesce(nullif(r.location,''), 'Unknown') as location,
    r.website_host,
    r.cohort_month,
    r.segment_label,
    r.primary_tag,
    r.primary_tag_median_q_score,
    r.performance_score,
    r.global_rank,
    r.segment_rank,
    r.perf_rank_in_cohort,
    r.reputation,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.last_badge_date,
    r.total_questions_lifetime,
    r.total_answers_lifetime,
    r.questions,
    r.answers,
    r.accepted_answers,
    r.question_views,
    r.question_score,
    r.avg_answers_per_question,
    r.closed_questions,
    r.total_closed_questions,
    r.first_closed_at,
    r.avg_dup_close_votes,
    r.q_net_votes,
    r.a_net_votes,
    r.bounty_gained,
    r.bounty_put_up,
    r.avg_votes_per_post,
    r.p90_question_views,
    r.comments,
    r.comment_score,
    r.last_comment_at,
    r.linked_questions,
    r.hot_linked_questions
from ranked r
where (
        r.performance_score > (
            select avg(performance_score) from scored
        )
        or r.segment_label in ('elite','veteran')
      )
  and (r.primary_tag is null
       or (lower(r.primary_tag) not like 'meta%' and lower(r.primary_tag) not like 'discussion%'))
  and (r.global_rank <= 500 or r.segment_rank <= 50 or r.perf_rank_in_cohort <= 20)
order by r.segment_label, r.segment_rank, r.global_rank, r.user_id
limit 1000;