-- {"query": "77.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3250}
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc_rep
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_badge_activity as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_stats as (
    select
        p.owneruserid as userid,
        count(*) filter (where p.posttypeid = 1) as questions,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as q_views,
        sum(coalesce(p.score,0)) filter (where p.posttypeid = 1) as q_score,
        count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as q_with_accept,
        percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as q_view_p50
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
answer_stats as (
    select
        p.owneruserid as userid,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score,0)) filter (where p.posttypeid = 2) as a_score,
        avg(coalesce(p.score,0)) filter (where p.posttypeid = 2) as a_score_avg,
        count(*) filter (where p.posttypeid = 2 and p.score > 0) as a_pos_answers
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
votes_agg as (
    select
        v.userid,
        count(*) filter (where v.votetypeid = 2) as cast_upvotes,
        count(*) filter (where v.votetypeid = 3) as cast_downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites_legacy,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as total_bounty_amount
    from votes v
    where v.userid is not null
    group by v.userid
),
comments_agg as (
    select
        c.userid,
        count(*) as comments_count,
        sum(coalesce(c.score,0)) as comments_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
post_history_flags as (
    select
        ph.userid,
        count(*) filter (where ph.posthistorytypeid in (10,12,14)) as mod_negative_events,
        count(*) filter (where ph.posthistorytypeid in (11,13,15)) as mod_positive_events,
        count(*) filter (where ph.posthistorytypeid in (35,36)) as migrations,
        count(*) filter (where ph.posthistorytypeid in (50,52)) as promoted_events
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
dupe_links as (
    select
        pl.postid,
        count(*) as duplicate_links
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid
),
question_tag_norm as (
    select
        p.id as postid,
        lower(trim(t)) as tag_norm
    from posts p,
    lateral (
        select unnest(
            case
                when p.tags is null then array[]::text[] 
                else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
            end
        ) as t
    ) u
    where p.posttypeid = 1
),
top_tags as (
    select
        qt.tag_norm,
        count(*) as tag_q_count,
        row_number() over (order by count(*) desc, qt.tag_norm) as rn_tag
    from question_tag_norm qt
    group by qt.tag_norm
),
user_top_tag as (
    select
        p.owneruserid as userid,
        qt.tag_norm,
        count(*) as user_tag_qs,
        row_number() over (partition by p.owneruserid order by count(*) desc, qt.tag_norm) as rn_user_tag
    from posts p
    join question_tag_norm qt on qt.postid = p.id
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid, qt.tag_norm
),
question_quality as (
    select
        q.id as postid,
        q.owneruserid as userid,
        q.score,
        q.viewcount,
        coalesce(dl.duplicate_links,0) as dupe_links,
        case
            when q.viewcount is null or q.viewcount = 0 then null
            else round((cast(q.score as numeric) / nullif(q.viewcount,0)), 6)
        end as score_per_view,
        case
            when q.closeddate is not null then 1
            when exists (
                select 1
                from posthistory ph
                where ph.postid = q.id and ph.posthistorytypeid = 10
            ) then 1
            else 0
        end as is_closed_or_voted_close
    from posts q
    left join dupe_links dl on dl.postid = q.id
    where q.posttypeid = 1 and q.owneruserid is not null
),
activity_span as (
    select
        u.id as userid,
        min(p.creationdate) as first_post_date,
        max(p.lastactivitydate) as last_activity_date,
        extract(epoch from (max(p.lastactivitydate) - min(p.creationdate))) / 86400.0 as active_days_span
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
user_post_summ as (
    select
        u.id as userid,
        count(*) as total_posts,
        count(*) filter (where p.posttypeid = 1) as total_questions,
        count(*) filter (where p.posttypeid = 2) as total_answers,
        sum(coalesce(p.score,0)) as total_post_score,
        avg(nullif(p.score,0)) filter (where p.posttypeid in (1,2)) as avg_nonzero_score,
        max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
user_vote_received as (
    select
        p.owneruserid as userid,
        count(*) filter (where v.votetypeid = 2) as upvotes_received,
        count(*) filter (where v.votetypeid = 3) as downvotes_received
    from posts p
    join votes v on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
ranked_users as (
    select
        ru.id as userid,
        ru.displayname,
        ru.location_norm,
        ru.cohort_month,
        ru.reputation,
        ru.rn_loc_rep,
        ua.total_badges,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        qs.questions,
        qs.q_views,
        qs.q_score,
        qs.q_with_accept,
        as2.answers,
        as2.a_score,
        as2.a_score_avg,
        va.cast_upvotes,
        va.cast_downvotes,
        va.favorites_legacy,
        va.bounties_interactions,
        va.total_bounty_amount,
        ca.comments_count,
        ca.comments_score,
        ph.mod_negative_events,
        ph.mod_positive_events,
        ph.migrations,
        ph.promoted_events,
        ups.total_posts,
        ups.total_questions,
        ups.total_answers,
        ups.total_post_score,
        ups.avg_nonzero_score,
        ups.last_post_date,
        uv.upvotes_received,
        uv.downvotes_received,
        act.first_post_date,
        act.last_activity_date,
        act.active_days_span,
        utt.tag_norm as top_tag,
        tt.tag_q_count as top_tag_global_qs
    from recent_users ru
    left join user_badge_activity ua on ua.userid = ru.id
    left join question_stats qs on qs.userid = ru.id
    left join answer_stats as2 on as2.userid = ru.id
    left join votes_agg va on va.userid = ru.id
    left join comments_agg ca on ca.userid = ru.id
    left join post_history_flags ph on ph.userid = ru.id
    left join user_post_summ ups on ups.userid = ru.id
    left join user_vote_received uv on uv.userid = ru.id
    left join activity_span act on act.userid = ru.id
    left join user_top_tag utt on utt.userid = ru.id and utt.rn_user_tag = 1
    left join top_tags tt on tt.tag_norm = utt.tag_norm
),
scored as (
    select
        r.*,
        coalesce(qc.qc_med, 0) as median_q_score_per_view,
        coalesce(qc.qc_closed_rate, 0.0) as closed_rate,
        case
            when coalesce(ups.total_posts,0) = 0 then 0
            else coalesce((cast(uv.upvotes_received as numeric) - cast(uv.downvotes_received as numeric)) / nullif(ups.total_posts,0), 0)
        end as net_votes_per_post,
        case
            when coalesce(as2.answers,0) = 0 then 0
            else (coalesce(as2.a_pos_answers,0) / nullif(as2.answers,0))
        end as positive_answer_ratio
    from ranked_users r
    left join lateral (
        select
            percentile_cont(0.5) within group (order by qq.score_per_view) as qc_med,
            avg(cast(qq.is_closed_or_voted_close as integer)) as qc_closed_rate
        from question_quality qq
        where qq.userid = r.userid
    ) qc on true
    left join answer_stats as2 on as2.userid = r.userid
    left join user_vote_received uv on uv.userid = r.userid
    left join user_post_summ ups on ups.userid = r.userid
),
normalized as (
    select
        s.*,
        (s.reputation - avg(s.reputation) over ()) / nullif(stddev_pop(s.reputation) over (),0) as z_rep,
        (coalesce(s.total_post_score,0) - avg(coalesce(s.total_post_score,0)) over ()) / nullif(stddev_pop(coalesce(s.total_post_score,0)) over (),0) as z_total_post_score,
        (coalesce(s.q_score,0) - avg(coalesce(s.q_score,0)) over ()) / nullif(stddev_pop(coalesce(s.q_score,0)) over (),0) as z_q_score,
        (coalesce(s.a_score,0) - avg(coalesce(s.a_score,0)) over ()) / nullif(stddev_pop(coalesce(s.a_score,0)) over (),0) as z_a_score,
        (coalesce(s.comments_score,0) - avg(coalesce(s.comments_score,0)) over ()) / nullif(stddev_pop(coalesce(s.comments_score,0)) over (),0) as z_comment_score
    from scored s
),
final_rank as (
    select
        n.*,
        (
            coalesce(z_rep,0) * 0.35
          + coalesce(z_total_post_score,0) * 0.25
          + coalesce(z_q_score,0) * 0.15
          + coalesce(z_a_score,0) * 0.15
          + coalesce(z_comment_score,0) * 0.10
        ) as composite_z,
        row_number() over (
            partition by n.location_norm
            order by
                (
                    coalesce(z_rep,0) * 0.35
                  + coalesce(z_total_post_score,0) * 0.25
                  + coalesce(z_q_score,0) * 0.15
                  + coalesce(z_a_score,0) * 0.15
                  + coalesce(z_comment_score,0) * 0.10
                ) desc,
                n.reputation desc,
                n.userid
        ) as rn_loc_composite
    from normalized n
),
cohort_summary as (
    select
        r.cohort_month,
        count(*) as users_in_cohort,
        avg(r.reputation) as avg_rep_cohort,
        percentile_cont(0.9) within group (order by r.reputation) as p90_rep_cohort
    from ranked_users r
    group by r.cohort_month
)
select
    fr.userid,
    fr.displayname,
    fr.location_norm,
    fr.cohort_month,
    fr.reputation,
    fr.total_posts,
    fr.total_questions,
    fr.total_answers,
    fr.total_post_score,
    fr.q_views,
    fr.q_score,
    fr.q_with_accept,
    fr.a_score,
    fr.a_score_avg,
    fr.comments_count,
    fr.comments_score,
    fr.cast_upvotes,
    fr.cast_downvotes,
    fr.upvotes_received,
    fr.downvotes_received,
    fr.total_badges,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.mod_negative_events,
    fr.mod_positive_events,
    fr.migrations,
    fr.promoted_events,
    fr.first_post_date,
    fr.last_post_date,
    fr.last_activity_date,
    fr.active_days_span,
    fr.top_tag,
    fr.top_tag_global_qs,
    fr.median_q_score_per_view,
    fr.closed_rate,
    fr.net_votes_per_post,
    fr.positive_answer_ratio,
    fr.composite_z,
    cs.users_in_cohort,
    cs.avg_rep_cohort,
    cs.p90_rep_cohort
from final_rank fr
left join cohort_summary cs on cs.cohort_month = fr.cohort_month
where fr.rn_loc_composite <= 10
order by fr.composite_z desc, fr.reputation desc, fr.userid
limit 200;