with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           date_trunc('month', u.creationdate) as cohort_month,
           row_number() over (order by u.reputation desc, u.id) as rn_global
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
user_activity as (
    select p.owneruserid as user_id,
           count(case when p.posttypeid = 1 then 1 end) as questions,
           count(case when p.posttypeid = 2 then 1 end) as answers,
           coalesce(sum(case when p.posttypeid in (1,2) then p.score else 0 end),0) as post_score,
           max(p.lastactivitydate) as last_post_activity,
           avg(nullif(p.viewcount,0)) as avg_views_nonzero
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by p.owneruserid
),
comment_activity as (
    select c.userid as user_id,
           count(*) as comments,
           coalesce(sum(c.score),0) as comment_score,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
      and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by c.userid
),
vote_activity as (
    select v.userid as user_id,
           count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
           count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
           count(case when v.votetypeid in (8,9) then 1 end) as bounty_events,
           sum(case when v.votetypeid in (8,9) then v.bountyamount else 0 end) as bounty_total
    from votes v
    where v.userid is not null
      and v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by v.userid
),
badges_agg as (
    select b.userid as user_id,
           count(case when b.class = 1 then 1 end) as gold_badges,
           count(case when b.class = 2 then 1 end) as silver_badges,
           count(case when b.class = 3 then 1 end) as bronze_badges,
           count(case when b.tagbased = true then 1 end) as tag_badges,
           max(b.date) as last_badge_date
    from badges b
    where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by b.userid
),
q_close_reasons as (
    select ph.postid,
           max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_date,
           max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_code
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)
    group by ph.postid
),
question_metrics as (
    select p.owneruserid as user_id,
           count(*) as total_questions,
           count(case when p.acceptedanswerid is not null then 1 end) as accepted_questions,
           avg(p.answercount) as avg_answers_per_q,
           avg(p.score) as avg_q_score,
           count(case when p.closeddate is not null then 1 end) as closed_questions,
           count(case when p.viewcount >= 1000 then 1 end) as q_over_1k_views,
           max(qc.last_closed_date) as last_closed_date_any
    from posts p
    left join q_close_reasons qc on qc.postid = p.id
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
      and p.owneruserid is not null
    group by p.owneruserid
),
answer_metrics as (
    select p.owneruserid as user_id,
           count(*) as total_answers,
           avg(p.score) as avg_a_score,
           count(case when p.score >= 1 then 1 end) as upvoted_answers,
           count(case when p.score <= -1 then 1 end) as downvoted_answers,
           count(distinct p.parentid) as distinct_questions_answered
    from posts p
    where p.posttypeid = 2
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
      and p.owneruserid is not null
    group by p.owneruserid
),
hot_streaks as (
    select pa.owneruserid as user_id,
           max(pa.score) as peak_post_score,
           max(pa.viewcount) as peak_post_views,
           min(case when pa.score = (select max(p2.score) from posts p2 where p2.owneruserid = pa.owneruserid and p2.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years') then pa.creationdate end) as first_peak_score_date
    from posts pa
    where pa.owneruserid is not null
      and pa.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by pa.owneruserid
),
tag_exposure as (
    select p.owneruserid as user_id,
           count(*) as tagged_questions,
           count(distinct tg) as distinct_tags_used,
           string_agg(distinct lower(trim(tg)), ', ' order by lower(trim(tg))) as tag_list_sample
    from posts p
         cross join lateral (
             select unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tg
         ) tagu
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by p.owneruserid
),
monthly_activity as (
    select u.id as user_id,
           date_trunc('month', p.creationdate) as m,
           count(case when p.posttypeid = 1 then 1 end) as q_monthly,
           count(case when p.posttypeid = 2 then 1 end) as a_monthly,
           count(c.id) as c_monthly
    from users u
    left join posts p on p.owneruserid = u.id
                      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    left join comments c on c.userid = u.id
                        and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
                        and date_trunc('month', c.creationdate) = date_trunc('month', coalesce(p.creationdate, c.creationdate))
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by u.id, date_trunc('month', p.creationdate)
),
monthly_summ as (
    select user_id,
           count(*) as active_months,
           avg(coalesce(q_monthly,0) + coalesce(a_monthly,0) + coalesce(c_monthly,0)) as avg_actions_per_active_month,
           max(q_monthly + a_monthly + c_monthly) as peak_actions_in_month
    from monthly_activity
    group by user_id
),
dup_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id,
           pl.creationdate as dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
      and pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
dup_user_impact as (
    select p.owneruserid as user_id,
           count(*) as duplicates_marked_against_user,
           max(d.dup_link_date) as last_dup_date
    from dup_links d
    join posts p on p.id = d.dup_post_id
    where p.owneruserid is not null
    group by p.owneruserid
),
recent_quality_window as (
    select p.owneruserid as user_id,
           avg(p.score) over (partition by p.owneruserid order by p.creationdate rows between 9 preceding and current row) as rolling_avg_score_10,
           avg(p.viewcount) over (partition by p.owneruserid order by p.creationdate rows between 9 preceding and current row) as rolling_avg_views_10,
           p.creationdate as post_date
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
latest_quality as (
    select user_id, rolling_avg_score_10, rolling_avg_views_10
    from (
      select distinct on (user_id) user_id, rolling_avg_score_10, rolling_avg_views_10, post_date
      from recent_quality_window
      order by user_id, post_date desc
    ) t
),
normalized as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.cohort_month,
           coalesce(ua.questions,0) as questions,
           coalesce(ua.answers,0) as answers,
           coalesce(ua.post_score,0) as post_score,
           coalesce(ca.comments,0) as comments,
           coalesce(ca.comment_score,0) as comment_score,
           coalesce(va.upvotes_cast,0) as upvotes_cast,
           coalesce(va.downvotes_cast,0) as downvotes_cast,
           coalesce(va.bounty_events,0) as bounty_events,
           coalesce(va.bounty_total,0) as bounty_total,
           coalesce(ba.gold_badges,0) as gold_badges,
           coalesce(ba.silver_badges,0) as silver_badges,
           coalesce(ba.bronze_badges,0) as bronze_badges,
           coalesce(ba.tag_badges,0) as tag_badges,
           coalesce(qm.total_questions,0) as total_questions,
           coalesce(qm.accepted_questions,0) as accepted_questions,
           coalesce(qm.avg_answers_per_q,0) as avg_answers_per_q,
           coalesce(qm.avg_q_score,0) as avg_q_score,
           coalesce(qm.closed_questions,0) as closed_questions,
           coalesce(qm.q_over_1k_views,0) as q_over_1k_views,
           coalesce(am.total_answers,0) as total_answers,
           coalesce(am.avg_a_score,0) as avg_a_score,
           coalesce(am.upvoted_answers,0) as upvoted_answers,
           coalesce(am.downvoted_answers,0) as downvoted_answers,
           coalesce(am.distinct_questions_answered,0) as distinct_questions_answered,
           coalesce(hs.peak_post_score,0) as peak_post_score,
           coalesce(hs.peak_post_views,0) as peak_post_views,
           coalesce(te.tagged_questions,0) as tagged_questions,
           coalesce(te.distinct_tags_used,0) as distinct_tags_used,
           te.tag_list_sample,
           coalesce(ms.active_months,0) as active_months,
           coalesce(ms.avg_actions_per_active_month,0) as avg_actions_per_active_month,
           coalesce(ms.peak_actions_in_month,0) as peak_actions_in_month,
           coalesce(dui.duplicates_marked_against_user,0) as duplicates_marked_against_user,
           lq.rolling_avg_score_10,
           lq.rolling_avg_views_10,
           greatest(coalesce(ua.last_post_activity, timestamp 'epoch'),
                    coalesce(ca.last_comment_date, timestamp 'epoch'),
                    coalesce(ba.last_badge_date, timestamp 'epoch'),
                    coalesce(qm.last_closed_date_any, timestamp 'epoch')) as last_any_activity
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join vote_activity va on va.user_id = ru.user_id
    left join badges_agg ba on ba.user_id = ru.user_id
    left join question_metrics qm on qm.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
    left join hot_streaks hs on hs.user_id = ru.user_id
    left join tag_exposure te on te.user_id = ru.user_id
    left join monthly_summ ms on ms.user_id = ru.user_id
    left join dup_user_impact dui on dui.user_id = ru.user_id
    left join latest_quality lq on lq.user_id = ru.user_id
),
ranked as (
    select n.*,
           (coalesce(questions,0) + coalesce(answers,0) + coalesce(comments,0)) as total_contributions,
           case when (coalesce(total_questions,0)) > 0 then round(100.0 * cast(accepted_questions as numeric) / nullif(total_questions,0), 2) else null end as q_accept_rate_pct,
           case when (coalesce(total_answers,0)) > 0 then round(100.0 * cast(upvoted_answers as numeric) / nullif(total_answers,0), 2) else null end as a_upvote_rate_pct,
           dense_rank() over (order by coalesce(post_score,0) + coalesce(comment_score,0) + coalesce(bounty_total,0) desc) as rnk_engagement,
           row_number() over (partition by cohort_month order by coalesce(post_score,0) desc, reputation desc) as rnk_in_cohort,
           ntile(10) over (order by coalesce(avg_a_score,0) desc) as decile_avg_a_score
    from normalized n
),
outliers as (
    select user_id,
           displayname,
           reputation,
           total_contributions,
           post_score,
           comment_score,
           peak_post_score,
           peak_post_views,
           case when post_score > 0 then cast(post_score as numeric) / nullif(total_contributions,0) end as score_per_contribution,
           case when peak_post_views > 0 then cast(peak_post_views as numeric) / greatest(1, distinct_questions_answered) end as peak_views_per_q_answered
    from ranked
)
select r.user_id,
       r.displayname,
       r.reputation,
       r.cohort_month,
       r.total_contributions,
       r.post_score,
       r.comment_score,
       r.upvotes_cast,
       r.downvotes_cast,
       r.bounty_total,
       r.gold_badges,
       r.silver_badges,
       r.bronze_badges,
       r.tagged_questions,
       r.distinct_tags_used,
       coalesce(r.tag_list_sample, '(no tags)') as tag_list_sample,
       r.total_questions,
       r.accepted_questions,
       r.avg_answers_per_q,
       r.avg_q_score,
       r.total_answers,
       r.avg_a_score,
       r.active_months,
       r.avg_actions_per_active_month,
       r.duplicates_marked_against_user,
       r.rolling_avg_score_10,
       r.rolling_avg_views_10,
       r.last_any_activity,
       r.rnk_engagement,
       r.rnk_in_cohort,
       r.decile_avg_a_score,
       case
           when r.total_contributions = 0 then 'inactive'
           when coalesce(r.post_score,0) + coalesce(r.comment_score,0) < 0 then 'controversial'
           when r.gold_badges >= 1 or r.reputation >= 20000 then 'elite'
           when r.accepted_questions >= 5 and r.avg_a_score >= 2 then 'helpful'
           else 'regular'
       end as user_segment,
       case when o.score_per_contribution is null then 0 else 1 end as is_outlier_candidate
from ranked r
left join outliers o on o.user_id = r.user_id
where (
        r.total_contributions > 0
        or r.reputation >= 1000
        or (r.gold_badges + r.silver_badges + r.bronze_badges) >= 3
      )
and (
        r.last_any_activity is null
        or r.last_any_activity >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    )
order by r.rnk_engagement, r.user_id
limit 500;