-- {"query": "868.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3690} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region_hint,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= now() - interval '5 years'
),
badge_summary as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
questions as (
    select
        p.id as question_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        p.closeddate,
        p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as user_id,
        a.creationdate,
        a.score
    from posts a
    where a.posttypeid = 2
),
engagement as (
    select
        q.user_id,
        count(*) as q_count,
        sum((q.score > 0)::int) as q_positive,
        sum(coalesce(q.viewcount,0)) as q_views,
        sum(coalesce(q.answercount,0)) as q_answers,
        count(q.acceptedanswerid) as q_with_accepted,
        count(*) filter (where q.closeddate is not null) as q_closed
    from questions q
    group by q.user_id
),
answer_engagement as (
    select
        a.user_id,
        count(*) as a_count,
        sum((a.score > 0)::int) as a_positive,
        sum(a.score) as a_score_sum
    from answers a
    group by a.user_id
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as c_count,
        sum((c.score > 0)::int) as c_positive,
        max(c.creationdate) as last_comment
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_activity as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        count(*) filter (where v.votetypeid = 9) as bounties_closed,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from votes v
    where v.userid is not null
    group by v.userid
),
postlinks_dupes as (
    select
        pl.postid as duplicate_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
duplication_stats as (
    select
        q.user_id,
        count(*) as dupes_marked,
        min(pd.first_link_date) as first_dupe_date
    from postlinks_dupes pd
    join posts q on q.id = pd.duplicate_post_id and q.posttypeid = 1
    group by q.user_id
),
posthistory_closes as (
    select
        ph.postid,
        ph.creationdate,
        ph.userid as closer_user_id,
        ph.comment,
        ph.text
    from posthistory ph
    where ph.posthistorytypeid in (10,35) -- closed or migrated away
),
closed_reason_agg as (
    select
        q.owneruserid as user_id,
        count(*) as close_events,
        count(*) filter (
            where coalesce(nullif(ph.comment,''),'0') ~ '^[0-9]+$' 
              and cast(ph.comment as int) in (101,102,103,104,105,1,2,3,4,7,10,20)
        ) as close_with_reason
    from posthistory_closes ph
    join posts q on q.id = ph.postid and q.posttypeid = 1
    group by q.owneruserid
),
user_first_last_posts as (
    select
        p.owneruserid as user_id,
        min(p.creationdate) as first_post_date,
        max(p.creationdate) as last_post_date
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
user_tag_pref as (
    select
        q.user_id,
        lower(trim(both '<>' from unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-1,0)), '><')))) as tag
    from questions q
    where q.tags is not null
),
top_tags as (
    select user_id, tag, cnt, rn
    from (
        select
            user_id,
            tag,
            count(*) as cnt,
            row_number() over (partition by user_id order by count(*) desc, tag) as rn
        from user_tag_pref
        group by user_id, tag
    ) s
    where rn <= 3
),
user_top_tags_pivot as (
    select
        user_id,
        max(tag) filter (where rn = 1) as top_tag_1,
        max(cnt) filter (where rn = 1) as top_tag_1_cnt,
        max(tag) filter (where rn = 2) as top_tag_2,
        max(cnt) filter (where rn = 2) as top_tag_2_cnt,
        max(tag) filter (where rn = 3) as top_tag_3,
        max(cnt) filter (where rn = 3) as top_tag_3_cnt
    from top_tags
    group by user_id
),
activity_calendar as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month,
        count(*) as posts_in_month
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '5 years'
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_rollup as (
    select
        user_id,
        sum(posts_in_month) as posts_5y,
        max(posts_in_month) as peak_posts_monthly,
        stddev_samp(posts_in_month::numeric) as posts_monthly_stddev
    from activity_calendar
    group by user_id
),
user_quality as (
    select
        u.id as user_id,
        coalesce(e.q_count,0) as q_count,
        coalesce(ae.a_count,0) as a_count,
        coalesce(e.q_positive,0) + coalesce(ae.a_positive,0) as total_positive_posts,
        coalesce(ae.a_score_sum,0) + coalesce(e.q_with_accepted,0)*5 as heuristic_score,
        case when coalesce(e.q_count,0) + coalesce(ae.a_count,0) = 0 then null
             else (coalesce(e.q_views,0)::numeric / nullif(coalesce(e.q_count,0),0))
        end as avg_q_views_per_q,
        case when coalesce(e.q_count,0) = 0 then 0 else e.q_with_accepted::numeric / e.q_count end as acceptance_ratio,
        coalesce(e.q_closed,0) as q_closed,
        coalesce(ds.dupes_marked,0) as dupes_marked
    from users u
    left join engagement e on e.user_id = u.id
    left join answer_engagement ae on ae.user_id = u.id
    left join duplication_stats ds on ds.user_id = u.id
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.region_hint,
        ru.cohort_month,
        bs.gold_cnt, bs.silver_cnt, bs.bronze_cnt,
        uq.q_count, uq.a_count, uq.total_positive_posts, uq.heuristic_score, uq.avg_q_views_per_q,
        uq.acceptance_ratio, uq.q_closed, uq.dupes_marked,
        ca.close_events, ca.close_with_reason,
        uf.first_post_date, uf.last_post_date,
        at.posts_5y, at.peak_posts_monthly, at.posts_monthly_stddev,
        tt.top_tag_1, tt.top_tag_1_cnt, tt.top_tag_2, tt.top_tag_2_cnt, tt.top_tag_3, tt.top_tag_3_cnt,
        row_number() over (
            order by
                coalesce(uq.heuristic_score,0) desc,
                coalesce(bs.gold_cnt,0) desc,
                coalesce(bs.silver_cnt,0) desc,
                ru.reputation desc,
                coalesce(uq.total_positive_posts,0) desc
        ) as overall_rank
    from recent_users ru
    left join badge_summary bs on bs.userid = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join closed_reason_agg ca on ca.user_id = ru.user_id
    left join user_first_last_posts uf on uf.user_id = ru.user_id
    left join activity_rollup at on at.user_id = ru.user_id
    left join user_top_tags_pivot tt on tt.user_id = ru.user_id
),
activity_gaps as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.creationdate,
        p.posttypeid,
        p.score,
        lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_date,
        extract(epoch from p.creationdate - lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate)) / 86400.0 as gap_days
    from posts p
    where p.owneruserid is not null
),
max_gaps as (
    select
        user_id,
        max(gap_days) as max_gap_days,
        avg(gap_days) as avg_gap_days
    from activity_gaps
    group by user_id
),
recent_text_signals as (
    select
        p.owneruserid as user_id,
        count(*) filter (where lower(coalesce(p.title,'')) like '%how do i%') as q_how_do_i,
        count(*) filter (where lower(coalesce(p.body,'')) like '%thanks%') as posts_say_thanks,
        count(*) filter (where lower(coalesce(p.body,'')) like '%error%') as posts_with_error,
        count(*) filter (where lower(coalesce(p.title,'')) ~ '\b(best|fastest|quickest)\b') as q_superlatives
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '2 years'
    group by p.owneruserid
),
user_flags as (
    select
        ru.user_id,
        (coalesce(bs.gold_cnt,0) >= 5 and coalesce(uq.acceptance_ratio,0) >= 0.25) as is_power_user,
        (coalesce(ds.dupes_marked,0) >= 1) as has_dupes,
        (coalesce(ca.close_events,0) > 0 and coalesce(ca.close_with_reason,0) = 0) as closes_without_reason,
        (coalesce(at.peak_posts_monthly,0) >= 20) as high_variance_producer
    from ranked_users ru
    left join badge_summary bs on bs.userid = ru.user_id
    left join duplication_stats ds on ds.user_id = ru.user_id
    left join closed_reason_agg ca on ca.user_id = ru.user_id
    left join activity_rollup at on at.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
),
cohort_stats as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        percentile_disc(0.5) within group (order by reputation) as median_rep,
        avg(heuristic_score) as avg_heuristic,
        percentile_disc(0.9) within group (order by coalesce(heuristic_score,0)) as p90_heuristic
    from ranked_users
    group by cohort_month
),
final_union as (
    select
        'user' as rowtype,
        ru.overall_rank::text as key,
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.region_hint,
        ru.cohort_month,
        ru.gold_cnt, ru.silver_cnt, ru.bronze_cnt,
        ru.q_count, ru.a_count, ru.total_positive_posts, ru.heuristic_score,
        round(coalesce(ru.avg_q_views_per_q,0)::numeric,2) as avg_q_views_per_q,
        round(coalesce(ru.acceptance_ratio,0)::numeric,3) as acceptance_ratio,
        ru.q_closed, ru.dupes_marked,
        coalesce(ca.close_events,0) as close_events, coalesce(ca.close_with_reason,0) as close_with_reason,
        uf.first_post_date, uf.last_post_date,
        at.posts_5y, at.peak_posts_monthly, at.posts_monthly_stddev,
        mg.max_gap_days, mg.avg_gap_days,
        rt.q_how_do_i, rt.posts_say_thanks, rt.posts_with_error, rt.q_superlatives,
        f.is_power_user, f.has_dupes, f.closes_without_reason, f.high_variance_producer,
        tt.top_tag_1, tt.top_tag_1_cnt, tt.top_tag_2, tt.top_tag_2_cnt, tt.top_tag_3, tt.top_tag_3_cnt,
        null::timestamp as cohort_or_null
    from ranked_users ru
    left join closed_reason_agg ca on ca.user_id = ru.user_id
    left join user_first_last_posts uf on uf.user_id = ru.user_id
    left join activity_rollup at on at.user_id = ru.user_id
    left join max_gaps mg on mg.user_id = ru.user_id
    left join recent_text_signals rt on rt.user_id = ru.user_id
    left join user_flags f on f.user_id = ru.user_id
    left join user_top_tags_pivot tt on tt.user_id = ru.user_id

    union all

    select
        'cohort' as rowtype,
        to_char(cs.cohort_month, 'YYYY-MM') as key,
        null::int as user_id,
        null::varchar as displayname,
        cs.median_rep as reputation,
        null::varchar as region_hint,
        cs.cohort_month,
        null::int as gold_cnt, null::int as silver_cnt, null::int as bronze_cnt,
        null::int as q_count, null::int as a_count, null::int as total_positive_posts, cs.avg_heuristic as heuristic_score,
        null::numeric as avg_q_views_per_q,
        null::numeric as acceptance_ratio,
        null::int as q_closed, null::int as dupes_marked,
        null::int as close_events, null::int as close_with_reason,
        null::timestamp as first_post_date, null::timestamp as last_post_date,
        null::int as posts_5y, null::int as peak_posts_monthly, null::numeric as posts_monthly_stddev,
        null::numeric as max_gap_days, null::numeric as avg_gap_days,
        null::int as q_how_do_i, null::int as posts_say_thanks, null::int as posts_with_error, null::int as q_superlatives,
        null::boolean as is_power_user, null::boolean as has_dupes, null::boolean as closes_without_reason, null::boolean as high_variance_producer,
        null::varchar as top_tag_1, null::int as top_tag_1_cnt, null::varchar as top_tag_2, null::int as top_tag_2_cnt, null::varchar as top_tag_3, null::int as top_tag_3_cnt,
        cs.cohort_month as cohort_or_null
    from cohort_stats cs
)
select *
from final_union
where (
    rowtype = 'user' and (
        coalesce(heuristic_score,0) > 10
        or coalesce(gold_cnt,0) >= 1
        or (coalesce(q_count,0) + coalesce(a_count,0)) >= 10
    )
)
or rowtype = 'cohort'
order by rowtype desc, reputation desc nulls last, key asc
limit 1000;