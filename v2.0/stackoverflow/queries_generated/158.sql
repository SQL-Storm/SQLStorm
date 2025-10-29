-- {"query": "158.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2919} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
tagged_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_array
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
),
tag_expansion as (
    select
        q.question_id,
        q.owneruserid,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.is_closed,
        lower(trim(t)) as tag
    from tagged_questions q
    cross join lateral unnest(q.tag_array) as t
),
core_tags as (
    select tagname as tag
    from tags
    where count > 1000
),
user_activity as (
    select
        u.user_id,
        u.cohort_month,
        count(distinct case when p.posttypeid in (1,2) then p.id end) as posts_authored,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
      and p.creationdate >= u.creationdate
    left join votes v
      on v.userid = u.user_id
      and v.creationdate >= u.creationdate
    left join badges b
      on b.userid = u.user_id
      and b.date >= u.creationdate
    group by u.user_id, u.cohort_month
),
q_metrics as (
    select
        q.question_id,
        q.owneruserid as user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.is_closed,
        avg(c.score) filter (where c.id is not null) as avg_comment_score,
        count(c.id) as comment_count,
        sum(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as mod_events,
        count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as dup_of_count
    from tagged_questions q
    left join comments c on c.postid = q.question_id
    left join posthistory ph on ph.postid = q.question_id
    left join postlinks pl on pl.postid = q.question_id
    group by q.question_id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.is_closed
),
accepted_answer_lag as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        case
            when q.acceptedanswerid is null then null
            else (select a.creationdate from posts a where a.id = q.acceptedanswerid)
        end as accepted_answer_date,
        q.creationdate as question_date
    from posts q
    where q.posttypeid = 1
),
answer_times as (
    select
        aal.question_id,
        aal.user_id,
        extract(epoch from (aal.accepted_answer_date - aal.question_date))::bigint as seconds_to_accept
    from accepted_answer_lag aal
),
user_tag_mix as (
    select
        te.owneruserid as user_id,
        te.tag,
        count(*) as tag_q_count,
        sum(case when te.tag in (select tag from core_tags) then 1 else 0 end) as in_core_tag
    from tag_expansion te
    group by te.owneruserid, te.tag
),
user_tag_rank as (
    select
        user_id,
        tag,
        tag_q_count,
        row_number() over (partition by user_id order by tag_q_count desc, tag asc) as tag_rank,
        sum(tag_q_count) over (partition by user_id) as total_q_by_user,
        sum(in_core_tag) over (partition by user_id) as core_tag_hits
    from user_tag_mix
),
user_rollups as (
    select
        ua.user_id,
        ua.cohort_month,
        ua.posts_authored,
        ua.upvotes_cast,
        ua.downvotes_cast,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ur.total_q_by_user,
        ur.core_tag_hits,
        max(case when ur.tag_rank = 1 then ur.tag end) as top_tag,
        max(case when ur.tag_rank = 1 then ur.tag_q_count end) as top_tag_q_count
    from user_activity ua
    left join user_tag_rank ur on ur.user_id = ua.user_id
    group by ua.user_id, ua.cohort_month, ua.posts_authored, ua.upvotes_cast, ua.downvotes_cast, ua.gold_badges, ua.silver_badges, ua.bronze_badges, ur.total_q_by_user, ur.core_tag_hits
),
question_quality as (
    select
        qm.question_id,
        qm.user_id,
        qm.creationdate,
        qm.score,
        qm.viewcount,
        qm.answercount,
        qm.is_closed,
        qm.avg_comment_score,
        qm.comment_count,
        qm.mod_events,
        qm.dup_of_count,
        at.seconds_to_accept,
        percentile_disc(0.5) within group (order by qm.score) over (partition by date_trunc('month', qm.creationdate)) as monthly_score_p50,
        percentile_disc(0.9) within group (order by coalesce(qm.viewcount,0)) over (partition by date_trunc('month', qm.creationdate)) as monthly_views_p90
    from q_metrics qm
    left join answer_times at on at.question_id = qm.question_id
),
user_question_windows as (
    select
        qq.user_id,
        qq.creationdate,
        qq.question_id,
        qq.score,
        qq.viewcount,
        qq.answercount,
        qq.is_closed,
        avg(qq.score) over (partition by qq.user_id order by qq.creationdate rows between 5 preceding and current row) as user_rolling_score_avg_6,
        sum(qq.viewcount) over (partition by qq.user_id order by qq.creationdate rows between unbounded preceding and current row) as user_cum_views,
        count(*) over (partition by qq.user_id order by qq.creationdate rows between unbounded preceding and current row) as user_q_count_to_date,
        sum(case when qq.is_closed = 1 then 1 else 0 end) over (partition by qq.user_id order by qq.creationdate rows between 10 preceding and current row) as recent_closed_11
    from question_quality qq
),
activity_grades as (
    select
        ur.user_id,
        ur.cohort_month,
        case
            when coalesce(ur.posts_authored,0) = 0 and coalesce(ur.upvotes_cast,0) = 0 then 'Dormant'
            when coalesce(ur.posts_authored,0) >= 50 or coalesce(ur.gold_badges,0) >= 1 then 'Power'
            when coalesce(ur.posts_authored,0) >= 10 then 'Active'
            else 'Casual'
        end as activity_segment,
        (coalesce(ur.upvotes_cast,0) - coalesce(ur.downvotes_cast,0)) as net_votes_cast,
        coalesce(ur.gold_badges,0) * 5 + coalesce(ur.silver_badges,0) * 2 + coalesce(ur.bronze_badges,0) as badge_score,
        case when nullif(trim(ur.top_tag), '') is null then 'none' else ur.top_tag end as top_tag_norm,
        coalesce(ur.top_tag_q_count,0) as top_tag_qs,
        coalesce(ur.total_q_by_user,0) as total_qs,
        case when coalesce(ur.total_q_by_user,0) = 0 then null
             else round(100.0 * coalesce(ur.core_tag_hits,0) / nullif(ur.total_q_by_user,0), 2)
        end as pct_core_tag_qs
    from user_rollups ur
),
question_flags as (
    select
        uw.user_id,
        uw.question_id,
        uw.creationdate,
        (uw.user_rolling_score_avg_6 < qq.monthly_score_p50) as below_month_median,
        (coalesce(uw.user_cum_views,0) > qq.monthly_views_p90) as above_month_views_p90,
        (uw.recent_closed_11 >= 2) as many_recent_closes
    from user_question_windows uw
    join question_quality qq on qq.question_id = uw.question_id
),
final_scores as (
    select
        qq.question_id,
        qq.user_id,
        qq.creationdate,
        qq.score,
        qq.viewcount,
        qq.answercount,
        qq.is_closed,
        qq.seconds_to_accept,
        af.activity_segment,
        af.badge_score,
        af.net_votes_cast,
        af.top_tag_norm,
        af.top_tag_qs,
        af.pct_core_tag_qs,
        qf.below_month_median,
        qf.above_month_views_p90,
        qf.many_recent_closes,
        (
            coalesce(qq.score,0) * 2
          + least(coalesce(qq.viewcount,0) / 100, 50)
          + case when qq.answercount >= 3 then 5 else 0 end
          + case when qq.seconds_to_accept is not null then greatest(0, 20 - least(qq.seconds_to_accept/3600, 20)) end
          + case when qf.above_month_views_p90 then 10 else 0 end
          - case when qf.below_month_median then 5 else 0 end
          - case when qq.is_closed = 1 then 15 else 0 end
          - coalesce(qq.dup_of_count,0) * 2
        ) as quality_score
    from question_quality qq
    left join question_flags qf on qf.question_id = qq.question_id
    left join activity_grades af on af.user_id = qq.user_id
),
ranked as (
    select
        fs.*,
        dense_rank() over (partition by date_trunc('month', fs.creationdate) order by fs.quality_score desc nulls last, fs.viewcount desc nulls last, fs.score desc nulls last, fs.question_id) as month_rank,
        row_number() over (partition by fs.user_id order by fs.quality_score desc nulls last, fs.creationdate desc, fs.question_id) as best_for_user_rank
    from final_scores fs
),
dedup as (
    select
        r.*
    from ranked r
    where r.best_for_user_rank <= 3
)
select
    d.question_id,
    d.user_id,
    to_char(d.creationdate, 'YYYY-MM') as month,
    d.quality_score,
    d.month_rank,
    d.score as raw_score,
    d.viewcount,
    d.answercount,
    coalesce(d.seconds_to_accept, -1) as seconds_to_accept,
    d.is_closed,
    coalesce(d.activity_segment, 'Unknown') as activity_segment,
    coalesce(d.badge_score, 0) as badge_score,
    coalesce(d.net_votes_cast, 0) as net_votes_cast,
    d.top_tag_norm,
    coalesce(d.top_tag_qs, 0) as top_tag_qs,
    d.pct_core_tag_qs,
    d.below_month_median,
    d.above_month_views_p90,
    d.many_recent_closes
from dedup d
where
    -- complicated predicate combining text, nulls, and math
    (
        d.activity_segment is null
        or d.activity_segment in ('Power','Active')
        or (d.top_tag_norm not in ('discussion','meta') and (d.badge_score + d.net_votes_cast) >= 0)
    )
    and coalesce(d.quality_score, -9999) > (
        select avg(coalesce(quality_score,0)) - 1.0 * stddev_pop(coalesce(quality_score,0))
        from final_scores
        where creationdate >= d.creationdate - interval '6 months'
          and creationdate < d.creationdate + interval '6 months'
    )
order by d.month_rank, d.quality_score desc, d.viewcount desc
limit 500;