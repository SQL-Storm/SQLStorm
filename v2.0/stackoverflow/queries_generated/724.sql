-- {"query": "724.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3325} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as region,
           date_trunc('month', u.creationdate) as cohort_month,
           dense_rank() over (order by date_trunc('month', u.creationdate) desc) as cohort_rank
    from users u
),
active_users as (
    select ru.*
    from recent_users ru
    where ru.cohort_rank <= 12
),
questions as (
    select p.id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.answercount,
           p.favoritecount,
           p.commentcount,
           p.acceptedanswerid,
           p.closeddate,
           p.tags,
           p.title
    from posts p
    where p.posttypeid = 1
),
answers as (
    select p.id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.commentcount
    from posts p
    where p.posttypeid = 2
),
user_q_activity as (
    select au.user_id,
           count(*) as q_count,
           avg(p.score) as q_avg_score,
           sum(case when p.acceptedanswerid is not null then 1 else 0 end) as q_with_accept,
           sum(case when p.closeddate is not null then 1 else 0 end) as q_closed,
           sum(coalesce(p.viewcount,0)) as q_views,
           avg(nullif(p.viewcount,0)) as q_avg_views_nonzero,
           min(p.creationdate) as first_q_date,
           max(p.creationdate) as last_q_date,
           sum(cardinality(string_to_array(coalesce(nullif(substring(p.tags, 2, length(p.tags)-2),''),''), '><'))) as q_total_tags
    from active_users au
    left join questions p on p.owneruserid = au.user_id
    group by au.user_id
),
user_a_activity as (
    select au.user_id,
           count(*) as a_count,
           avg(a.score) as a_avg_score,
           sum(case when a.score > 0 then 1 else 0 end) as a_positive,
           sum(case when a.score < 0 then 1 else 0 end) as a_negative,
           min(a.creationdate) as first_a_date,
           max(a.creationdate) as last_a_date
    from active_users au
    left join answers a on a.user_id = au.user_id
    group by au.user_id
),
user_comment_activity as (
    select au.user_id,
           count(c.id) as c_count,
           avg(c.score) as c_avg_score,
           max(c.creationdate) as last_c_date
    from active_users au
    left join comments c on c.userid = au.user_id
    group by au.user_id
),
user_badges as (
    select au.user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from active_users au
    left join badges b on b.userid = au.user_id
    group by au.user_id
),
question_close_reasons as (
    select ph.postid,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id,
           max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_date
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
dup_links as (
    select pl.postid as dup_post_id,
           count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    group by pl.postid
),
post_votes as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
           count(*) filter (where v.votetypeid in (10,11,12)) as mod_actions
    from votes v
    group by v.postid
),
user_post_vote_agg as (
    select au.user_id,
           sum(coalesce(pv.upvotes,0)) as total_upvotes_rcvd,
           sum(coalesce(pv.downvotes,0)) as total_downvotes_rcvd,
           sum(coalesce(pv.bounty_started,0)) as total_bounty_started,
           sum(coalesce(pv.bounty_awarded,0)) as total_bounty_awarded,
           sum(coalesce(pv.mod_actions,0)) as total_mod_actions
    from active_users au
    left join posts p on p.owneruserid = au.user_id
    left join post_votes pv on pv.postid = p.id
    group by au.user_id
),
accepted_answer_latency as (
    select q.owneruserid as user_id,
           avg(extract(epoch from (aa.creationdate - q.creationdate)) / 3600.0) as avg_accept_latency_hours
    from posts q
    join posts aa on aa.id = q.acceptedanswerid
    where q.posttypeid = 1
    group by q.owneruserid
),
response_time as (
    select q.owneruserid as asker_id,
           avg(extract(epoch from (first_value(a.creationdate) over (partition by q.id order by a.creationdate) - q.creationdate)) / 60.0) as avg_first_answer_minutes
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.owneruserid, q.id
),
response_time_agg as (
    select asker_id as user_id,
           avg(avg_first_answer_minutes) as avg_first_answer_minutes
    from response_time
    group by asker_id
),
user_activity_span as (
    select au.user_id,
           greatest(
               coalesce(extract(epoch from (coalesce(ua.last_a_date, au.cohort_month) - au.cohort_month)), 0),
               coalesce(extract(epoch from (coalesce(uq.last_q_date, au.cohort_month) - au.cohort_month)), 0),
               coalesce(extract(epoch from (coalesce(uc.last_c_date, au.cohort_month) - au.cohort_month)), 0)
           ) / 86400.0 as active_days_span
    from active_users au
    left join user_a_activity ua on ua.user_id = au.user_id
    left join user_q_activity uq on uq.user_id = au.user_id
    left join user_comment_activity uc on uc.user_id = au.user_id
),
user_quality_score as (
    select au.user_id,
           (
             0.4 * coalesce(ua.a_avg_score, 0) +
             0.3 * coalesce(uq.q_avg_score, 0) +
             0.2 * (coalesce(upv.total_upvotes_rcvd,0) - 0.5 * coalesce(upv.total_downvotes_rcvd,0)) / nullif(coalesce(ua.a_count,0) + coalesce(uq.q_count,0), 0) +
             0.1 * least(coalesce(ub.gold,0) * 5 + coalesce(ub.silver,0) * 2 + coalesce(ub.bronze,0) * 1, 100)
           ) as quality_score
    from active_users au
    left join user_a_activity ua on ua.user_id = au.user_id
    left join user_q_activity uq on uq.user_id = au.user_id
    left join user_badges ub on ub.user_id = au.user_id
    left join user_post_vote_agg upv on upv.user_id = au.user_id
),
user_flags as (
    select au.user_id,
           case when uq.q_closed > 0 then 1 else 0 end as any_closed_q,
           case when (coalesce(uq.q_count,0) + coalesce(ua.a_count,0)) = 0 then 1 else 0 end as inactive_poster,
           case when coalesce(ub.tag_badges,0) > 0 then 1 else 0 end as is_tag_badged
    from active_users au
    left join user_q_activity uq on uq.user_id = au.user_id
    left join user_a_activity ua on ua.user_id = au.user_id
    left join user_badges ub on ub.user_id = au.user_id
),
regional_stats as (
    select au.region,
           count(*) as users_in_region,
           avg(au.reputation) as avg_rep_region
    from active_users au
    group by au.region
),
ranked_users as (
    select au.user_id,
           au.displayname,
           au.reputation,
           au.region,
           au.cohort_month,
           uq.q_count,
           ua.a_count,
           uc.c_count,
           coalesce(uq.q_views,0) as q_views,
           coalesce(upv.total_upvotes_rcvd,0) as total_upvotes_rcvd,
           coalesce(upv.total_downvotes_rcvd,0) as total_downvotes_rcvd,
           coalesce(ub.gold,0) as gold_badges,
           coalesce(ub.silver,0) as silver_badges,
           coalesce(ub.bronze,0) as bronze_badges,
           coalesce(ub.tag_badges,0) as tag_badges,
           coalesce(qcr.last_close_reason_id, 0) as last_close_reason_id_any_q,
           coalesce(dpl.duplicate_links, 0) as duplicate_links_any_q,
           coalesce(al.avg_accept_latency_hours, null) as avg_accept_latency_hours,
           coalesce(rta.avg_first_answer_minutes, null) as avg_first_answer_minutes,
           uas.active_days_span,
           uqs.quality_score,
           rs.users_in_region,
           rs.avg_rep_region,
           row_number() over (
               partition by au.region
               order by
                   coalesce(uqs.quality_score, -1e9) desc,
                   coalesce(uq.q_count,0) + coalesce(ua.a_count,0) desc,
                   au.reputation desc
           ) as regional_rank
    from active_users au
    left join user_q_activity uq on uq.user_id = au.user_id
    left join user_a_activity ua on ua.user_id = au.user_id
    left join user_comment_activity uc on uc.user_id = au.user_id
    left join user_badges ub on ub.user_id = au.user_id
    left join user_post_vote_agg upv on upv.user_id = au.user_id
    left join accepted_answer_latency al on al.user_id = au.user_id
    left join response_time_agg rta on rta.user_id = au.user_id
    left join user_activity_span uas on uas.user_id = au.user_id
    left join user_quality_score uqs on uqs.user_id = au.user_id
    left join user_flags uf on uf.user_id = au.user_id
    left join regional_stats rs on rs.region = au.region
    left join lateral (
        select max(coalesce(qcr.last_close_reason_id,0)) as last_close_reason_id
        from questions q
        left join question_close_reasons qcr on qcr.postid = q.id
        where q.owneruserid = au.user_id
    ) lqcr on true
    left join lateral (
        select sum(coalesce(dl.duplicate_links,0)) as duplicate_links
        from questions q
        left join dup_links dl on dl.dup_post_id = q.id
        where q.owneruserid = au.user_id
    ) dpl on true
),
topn as (
    select *
    from ranked_users
    where regional_rank <= 10
),
tag_popularity as (
    select t.tagname,
           t.count,
           dense_rank() over (order by t.count desc) as tag_rank
    from tags t
),
user_top_tags as (
    select q.owneruserid as user_id,
           unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from questions q
    where q.tags is not null and q.tags like '<%>'
),
user_tag_scores as (
    select utt.user_id,
           utt.tag,
           count(*) as tag_q_count
    from user_top_tags utt
    group by utt.user_id, utt.tag
),
best_user_tag as (
    select uts.user_id,
           first_value(uts.tag) over (partition by uts.user_id order by uts.tag_q_count desc, uts.tag asc) as top_tag,
           first_value(uts.tag_q_count) over (partition by uts.user_id order by uts.tag_q_count desc, uts.tag asc) as top_tag_q_count
    from user_tag_scores uts
),
final as (
    select t.*,
           coalesce(but.top_tag, 'none') as top_tag,
           coalesce(but.top_tag_q_count, 0) as top_tag_q_count,
           tp.tag_rank as top_tag_global_rank
    from topn t
    left join best_user_tag but on but.user_id = t.user_id
    left join tag_popularity tp on tp.tagname = but.top_tag
)
select
    f.region,
    f.cohort_month,
    f.regional_rank,
    f.user_id,
    f.displayname,
    f.reputation,
    f.q_count,
    f.a_count,
    f.c_count,
    f.q_views,
    f.total_upvotes_rcvd,
    f.total_downvotes_rcvd,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.tag_badges,
    f.last_close_reason_id_any_q,
    f.duplicate_links_any_q,
    round(f.avg_accept_latency_hours::numeric, 2) as avg_accept_latency_hours,
    round(f.avg_first_answer_minutes::numeric, 2) as avg_first_answer_minutes,
    round(f.active_days_span::numeric, 2) as active_days_span,
    round(f.quality_score::numeric, 4) as quality_score,
    f.users_in_region,
    round(f.avg_rep_region::numeric, 2) as avg_rep_region,
    f.top_tag,
    f.top_tag_q_count,
    f.top_tag_global_rank
from final f
where (
    f.quality_score > (
        select avg(quality_score) from ranked_users where region = f.region
    )
    or f.gold_badges > 0
)
order by f.region, f.regional_rank, f.quality_score desc, f.user_id
limit 500;