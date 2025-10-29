with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as rn_in_cohort
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_cnt,
        count(*) filter (where p.posttypeid = 2) as a_cnt,
        sum(coalesce(p.viewcount,0)) as total_views,
        sum(coalesce(p.score,0)) as total_post_score,
        max(p.lastactivitydate) as last_post_activity,
        count(distinct case when p.posttypeid = 1 then p.id end) as distinct_questions,
        count(distinct case when p.posttypeid = 2 then p.parentid end) as distinct_answered_questions
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comment_cnt,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_activity
    from comments c
    where c.userid is not null
      and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by c.userid
),
vote_activity as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
        sum(coalesce(v.bountyamount,0)) as bounty_amount_total,
        max(v.creationdate) as last_vote_activity
    from votes v
    where v.userid is not null
      and v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by v.userid
),
badges_activity as (
    select
        b.userid as user_id,
        count(*) as badge_cnt,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        count(*) filter (where b.tagbased = true) as tag_based_cnt,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by b.userid
),
question_quality as (
    select
        q.owneruserid as user_id,
        percentile_cont(0.5) within group (order by coalesce(q.score,0)) as q_median_score,
        avg(coalesce(q.viewcount,0)) as q_avg_views,
        avg(coalesce(q.answercount,0)) as q_avg_answers,
        sum(case when q.acceptedanswerid is not null then 1 else 0 end) as q_with_accept,
        count(*) as q_total
    from posts q
    where q.posttypeid = 1
      and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by q.owneruserid
),
answer_quality as (
    select
        a.owneruserid as user_id,
        percentile_cont(0.5) within group (order by coalesce(a.score,0)) as a_median_score,
        avg(coalesce(a.score,0)) as a_avg_score,
        sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as a_accepted_cnt,
        count(*) as a_total
    from posts a
    left join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
      and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by a.owneruserid
),
duplicate_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_outgoing_cnt,
        count(*) filter (where pl.linktypeid = 1) as linked_outgoing_cnt
    from postlinks pl
    where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by pl.postid
),
post_close_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(ph.creationdate) as last_close_event
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
      and ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by ph.postid
),
tag_extracted as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2, 0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
top_tags as (
    select
        tt.user_id,
        array_agg(t.tagname order by tt.cnt desc, t.tagname) filter (where tt.rn <= 5) as top5_tags
    from (
        select user_id, tagname, count(*) as cnt,
               row_number() over (partition by user_id order by count(*) desc, tagname) as rn
        from tag_extracted
        group by user_id, tagname
    ) tt
    join tags t on t.tagname = tt.tagname
    group by tt.user_id
),
user_last_activity as (
    select
        u.id as user_id,
        greatest(
            coalesce(ua.last_post_activity, timestamp 'epoch'),
            coalesce(ca.last_comment_activity, timestamp 'epoch'),
            coalesce(va.last_vote_activity, timestamp 'epoch'),
            coalesce(ba.last_badge_date, timestamp 'epoch')
        ) as last_activity
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join comment_activity ca on ca.user_id = u.id
    left join vote_activity va on va.user_id = u.id
    left join badges_activity ba on ba.user_id = u.id
),
power_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ua.q_cnt,
        ua.a_cnt,
        ca.comment_cnt,
        va.upvotes_cast,
        va.downvotes_cast,
        ba.badge_cnt,
        qq.q_median_score,
        aq.a_median_score,
        ua.total_post_score,
        ua.total_views,
        aq.a_accepted_cnt,
        qq.q_with_accept,
        ru.website_host,
        ul.last_activity,
        case
            when (coalesce(ua.q_cnt,0) + coalesce(ua.a_cnt,0)) = 0 then null
            else round(coalesce(ua.total_post_score,0) / nullif((coalesce(ua.q_cnt,0) + coalesce(ua.a_cnt,0)),0), 3)
        end as avg_score_per_post,
        case
            when coalesce(ua.q_cnt,0) = 0 then null
            else round(coalesce(qq.q_with_accept,0) / nullif(ua.q_cnt,0), 3)
        end as q_accept_rate,
        case
            when coalesce(aq.a_total,0) = 0 then null
            else round(coalesce(aq.a_accepted_cnt,0) / nullif(aq.a_total,0), 3)
        end as a_accept_share,
        coalesce(tt.top5_tags, array['']) as top5_tags,
        row_number() over (
            partition by ru.cohort_month
            order by
                coalesce(ua.total_post_score,0) desc,
                coalesce(va.upvotes_cast,0) desc,
                coalesce(ba.badge_cnt,0) desc,
                ru.reputation desc,
                ru.user_id
        ) as rank_in_cohort
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join vote_activity va on va.user_id = ru.user_id
    left join badges_activity ba on ba.user_id = ru.user_id
    left join question_quality qq on qq.user_id = ru.user_id
    left join answer_quality aq on aq.user_id = ru.user_id
    left join user_last_activity ul on ul.user_id = ru.user_id
    left join top_tags tt on tt.user_id = ru.user_id
),
post_penalties as (
    select
        p.owneruserid as user_id,
        sum(coalesce(dl.dup_outgoing_cnt,0)) as dup_links_out,
        sum(coalesce(dl.linked_outgoing_cnt,0)) as linked_links_out,
        sum(coalesce(pce.close_events,0)) as close_events,
        sum(coalesce(pce.reopen_events,0)) as reopen_events,
        sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts
    from posts p
    left join duplicate_links dl on dl.postid = p.id
    left join post_close_events pce on pce.postid = p.id
    where p.owneruserid is not null
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    group by p.owneruserid
),
score_buckets as (
    select
        pu.user_id,
        case
            when coalesce(pu.avg_score_per_post, 0) < -5 then 0
            when coalesce(pu.avg_score_per_post, 0) >= 15 then 11
            else cast(floor( (coalesce(pu.avg_score_per_post, 0) - (-5)) / ((15 - (-5)) / 10.0) ) as integer) + 1
        end as score_bucket
    from power_users pu
),
bench_base as (
    select
        pu.user_id,
        pu.displayname,
        pu.reputation,
        pu.cohort_month,
        pu.q_cnt,
        pu.a_cnt,
        pu.comment_cnt,
        pu.upvotes_cast,
        pu.downvotes_cast,
        pu.badge_cnt,
        pu.q_median_score,
        pu.a_median_score,
        pu.total_post_score,
        pu.total_views,
        pu.a_accepted_cnt,
        pu.q_with_accept,
        pu.website_host,
        pu.last_activity,
        pu.avg_score_per_post,
        pu.q_accept_rate,
        pu.a_accept_share,
        pu.top5_tags,
        pu.rank_in_cohort,
        pp.dup_links_out,
        pp.linked_links_out,
        pp.close_events,
        pp.reopen_events,
        pp.closed_posts,
        sb.score_bucket
    from power_users pu
    left join post_penalties pp on pp.user_id = pu.user_id
    left join score_buckets sb on sb.user_id = pu.user_id
    where pu.rank_in_cohort <= 200
),
agg_by_host as (
    select
        website_host,
        count(*) as user_cnt,
        avg(coalesce(avg_score_per_post,0)) as avg_score_per_post_host,
        avg(coalesce(q_median_score,0)) as avg_q_median_score_host,
        avg(coalesce(a_median_score,0)) as avg_a_median_score_host,
        sum(coalesce(dup_links_out,0)) as total_dup_links,
        sum(coalesce(close_events,0)) as total_close_events
    from bench_base
    group by website_host
),
host_rank as (
    select
        ah.website_host,
        ah.user_cnt,
        ah.avg_score_per_post_host,
        ah.avg_q_median_score_host,
        ah.avg_a_median_score_host,
        ah.total_dup_links,
        ah.total_close_events,
        dense_rank() over (order by ah.user_cnt desc, ah.avg_score_per_post_host desc, ah.website_host) as host_rank
    from agg_by_host ah
),
cohort_summary as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        avg(coalesce(avg_score_per_post,0)) as cohort_avg_score_per_post,
        percentile_cont(0.5) within group (order by coalesce(total_post_score,0)) as cohort_median_total_score,
        avg(coalesce(a_accept_share,0)) as cohort_avg_a_accept_share
    from bench_base
    group by cohort_month
),
final_rank as (
    select
        bb.*,
        row_number() over (
            order by
                (coalesce(total_post_score,0) * 2
                + coalesce(upvotes_cast,0)
                - coalesce(downvotes_cast,0)
                + coalesce(badge_cnt,0) * 3
                - coalesce(close_events,0) * 5
                - coalesce(dup_links_out,0) * 2
                + coalesce(a_accepted_cnt,0) * 4
                + coalesce(q_with_accept,0) * 2) desc,
                reputation desc,
                last_activity desc,
                user_id
        ) as global_rank
    from bench_base bb
)
select
    fr.global_rank,
    fr.user_id,
    fr.displayname,
    fr.reputation,
    fr.cohort_month,
    fr.rank_in_cohort,
    cs.users_in_cohort,
    cs.cohort_avg_score_per_post,
    cs.cohort_median_total_score,
    fr.q_cnt,
    fr.a_cnt,
    fr.comment_cnt,
    fr.total_post_score,
    fr.total_views,
    fr.upvotes_cast,
    fr.downvotes_cast,
    fr.badge_cnt,
    fr.q_median_score,
    fr.a_median_score,
    fr.a_accepted_cnt,
    fr.q_with_accept,
    fr.avg_score_per_post,
    fr.q_accept_rate,
    fr.a_accept_share,
    fr.top5_tags,
    fr.website_host,
    hr.host_rank,
    fr.dup_links_out,
    fr.linked_links_out,
    fr.close_events,
    fr.reopen_events,
    fr.closed_posts,
    fr.score_bucket,
    fr.last_activity
from final_rank fr
left join cohort_summary cs on cs.cohort_month = fr.cohort_month
left join host_rank hr on hr.website_host = fr.website_host
where coalesce(fr.q_cnt,0) + coalesce(fr.a_cnt,0) + coalesce(fr.comment_cnt,0) > 0
order by fr.global_rank
limit 500;