with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(p.creationdate) from posts p) - interval '3 years'
),
user_badge_counts as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        count(*) as total_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_activity as (
    select
        q.owneruserid as userid,
        count(*) filter (where q.posttypeid = 1) as questions,
        sum(coalesce(q.viewcount,0)) filter (where q.posttypeid = 1) as question_views,
        sum(coalesce(q.score,0)) filter (where q.posttypeid = 1) as question_score,
        sum(coalesce(q.favoritecount,0)) filter (where q.posttypeid = 1) as favorites,
        count(*) filter (where q.acceptedanswerid is not null) as accepted_questions,
        avg(nullif(q.answercount,0)) filter (where q.posttypeid = 1) as avg_answers_per_q
    from posts q
    where q.posttypeid = 1
    group by q.owneruserid
),
answer_activity as (
    select
        a.owneruserid as userid,
        count(*) as answers,
        sum(coalesce(a.score,0)) as answer_score,
        sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
        sum(case when a.score < 0 then 1 else 0 end) as negative_answers
    from posts a
    where a.posttypeid = 2
    group by a.owneruserid
),
comment_activity as (
    select
        c.userid as userid,
        count(*) as comments,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
vote_breakdown as (
    select
        v.userid as userid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upmods_cast,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downmods_cast,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounties_started_amt,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounties_awarded_amt,
        min(v.creationdate) as first_vote_date,
        max(v.creationdate) as last_vote_date
    from votes v
    group by v.userid
),
post_linking as (
    select
        p.owneruserid as userid,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as links_made,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicates_marked
    from postlinks pl
    join posts p on p.id = pl.postid
    group by p.owneruserid
),
closure_events as (
    select
        ph.userid as userid,
        sum(case when ph.posthistorytypeid in (10,11) then 1 else 0 end) as close_reopen_votes,
        sum(case when ph.posthistorytypeid = 10 and cast(ph.comment as integer) in (101,102,103,104,105) then 1 else 0 end) as closes_with_reason_new,
        sum(case when ph.posthistorytypeid = 10 and cast(ph.comment as integer) in (1,2,3,4,7,10,20) then 1 else 0 end) as closes_with_reason_old
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.userid
),
user_posts_cte as (
    select
        p.owneruserid as userid,
        count(*) as posts_total,
        max(p.lastactivitydate) as last_post_activity,
        sum(coalesce(p.score,0)) as post_score_total,
        sum(coalesce(p.commentcount,0)) as post_comment_count,
        sum(case when p.communityowneddate is not null then 1 else 0 end) as community_posts,
        sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts
    from posts p
    group by p.owneruserid
),
tag_exposure as (
    select
        p.owneruserid as userid,
        count(distinct t.tagname) as distinct_tags,
        string_agg(distinct lower(t.tagname), ',' order by lower(t.tagname)) as tag_list_sample
    from posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    ) t
    where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
    group by p.owneruserid
),
rep_velocity as (
    select
        u.id as userid,
        u.reputation,
        extract(epoch from (coalesce(nullif(u.lastaccessdate, u.creationdate), u.creationdate) - u.creationdate))/86400.0 as active_days,
        case
            when extract(epoch from (coalesce(nullif(u.lastaccessdate, u.creationdate), u.creationdate) - u.creationdate)) <= 0 then null
            else u.reputation / nullif(extract(epoch from (coalesce(nullif(u.lastaccessdate, u.creationdate), u.creationdate) - u.creationdate))/86400.0, 0)
        end as rep_per_day
    from users u
),
recent_quality_window as (
    select
        p.owneruserid as userid,
        avg(p.score) filter (where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') as avg_post_score_90d,
        percentile_cont(0.9) within group (order by coalesce(p.score,0)) as p90_post_score_all_time
    from posts p
    group by p.owneruserid
),
user_ranked as (
    select
        ru.id as userid,
        ru.displayname,
        ru.location,
        ru.websiteurl_norm,
        ru.cohort_month,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_count,0) as gold_badges,
        coalesce(ub.silver_count,0) as silver_badges,
        coalesce(ub.bronze_count,0) as bronze_badges,
        coalesce(qa.questions,0) as questions,
        coalesce(qa.question_views,0) as question_views,
        coalesce(qa.question_score,0) as question_score,
        coalesce(qa.favorites,0) as favorites,
        coalesce(qa.accepted_questions,0) as accepted_questions,
        coalesce(aa.answers,0) as answers,
        coalesce(aa.answer_score,0) as answer_score,
        coalesce(aa.positive_answers,0) as positive_answers,
        coalesce(aa.negative_answers,0) as negative_answers,
        coalesce(ca.comments,0) as comments,
        coalesce(ca.comment_score,0) as comment_score,
        coalesce(vb.upmods_cast,0) as upmods_cast,
        coalesce(vb.downmods_cast,0) as downmods_cast,
        coalesce(vb.favorites_cast,0) as favorites_cast,
        coalesce(vb.bounties_started_amt,0) as bounties_started_amt,
        coalesce(vb.bounties_awarded_amt,0) as bounties_awarded_amt,
        coalesce(pl.links_made,0) as links_made,
        coalesce(pl.duplicates_marked,0) as duplicates_marked,
        coalesce(ce.close_reopen_votes,0) as close_reopen_votes,
        coalesce(ce.closes_with_reason_new,0) as closes_with_reason_new,
        coalesce(ce.closes_with_reason_old,0) as closes_with_reason_old,
        coalesce(up.posts_total,0) as posts_total,
        coalesce(up.post_score_total,0) as post_score_total,
        coalesce(up.post_comment_count,0) as post_comment_count,
        coalesce(up.community_posts,0) as community_posts,
        coalesce(up.closed_posts,0) as closed_posts,
        coalesce(te.distinct_tags,0) as distinct_tags,
        te.tag_list_sample,
        rv.reputation,
        rv.rep_per_day,
        rq.avg_post_score_90d,
        rq.p90_post_score_all_time,
        greatest(coalesce(up.last_post_activity, ru.creationdate), coalesce(ca.last_comment_date, ru.creationdate), coalesce(vb.last_vote_date, ru.creationdate)) as last_activity_any
    from recent_users ru
    left join user_badge_counts ub on ub.userid = ru.id
    left join question_activity qa on qa.userid = ru.id
    left join answer_activity aa on aa.userid = ru.id
    left join comment_activity ca on ca.userid = ru.id
    left join vote_breakdown vb on vb.userid = ru.id
    left join post_linking pl on pl.userid = ru.id
    left join closure_events ce on ce.userid = ru.id
    left join user_posts_cte up on up.userid = ru.id
    left join tag_exposure te on te.userid = ru.id
    left join rep_velocity rv on rv.userid = ru.id
    left join recent_quality_window rq on rq.userid = ru.id
),
ranked_with_windows as (
    select
        ur.*,
        row_number() over (order by coalesce(ur.answers,0) + coalesce(ur.questions,0) desc, ur.reputation desc) as rownum_by_activity,
        rank() over (partition by ur.cohort_month order by ur.reputation desc) as rank_in_cohort_by_rep,
        dense_rank() over (order by coalesce(ur.p90_post_score_all_time,0) desc) as dense_rank_by_p90_score,
        sum(coalesce(ur.post_score_total,0)) over (order by ur.last_activity_any rows between unbounded preceding and current row) as running_total_post_score_by_activity_time,
        avg(coalesce(ur.rep_per_day,0)) over (partition by ur.cohort_month) as avg_rep_per_day_in_cohort
    from user_ranked ur
),
heavy_predicate as (
    select
        r.*,
        case
            when coalesce(r.answers,0) > 0 then (cast(coalesce(r.answer_score,0) as numeric) / nullif(r.answers,0))
            else null
        end as avg_answer_score,
        case
            when coalesce(r.questions,0) > 0 then (cast(coalesce(r.question_score,0) as numeric) / nullif(r.questions,0))
            else null
        end as avg_question_score,
        (coalesce(r.upmods_cast,0) - coalesce(r.downmods_cast,0)) as net_votes_cast,
        (coalesce(r.duplicates_marked,0) + coalesce(r.closes_with_reason_new,0) + coalesce(r.closes_with_reason_old,0)) as moderation_touches,
        case when r.tag_list_sample is null or r.tag_list_sample = '' then 0 else array_length(string_to_array(r.tag_list_sample, ','),1) end as tag_count_check,
        case when position('http' in coalesce(r.websiteurl_norm,'')) > 0 then 1 else 0 end as has_website_http
    from ranked_with_windows r
),
limits as (
    select
        *
    from heavy_predicate hp
    where
        coalesce(hp.rep_per_day, 0) >= (
            select percentile_cont(0.75) within group (order by coalesce(rep_per_day,0))
            from heavy_predicate
        )
        and (coalesce(hp.avg_answer_score, -999) >= 0 or coalesce(hp.avg_question_score, -999) >= 0)
        and coalesce(hp.distinct_tags,0) >= 3
        and (hp.last_activity_any >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' or hp.total_badges >= 5)
),
dupe_resolution as (
    select distinct on (l.userid)
        l.*,
        row_number() over (partition by l.userid order by l.reputation desc, l.answers desc, l.last_activity_any desc) as tie_breaker
    from limits l
)
select
    d.userid,
    coalesce(d.displayname, concat('user-', cast(d.userid as text))) as displayname_fallback,
    d.location,
    d.websiteurl_norm,
    d.cohort_month,
    d.reputation,
    d.rep_per_day,
    d.questions,
    d.answers,
    d.avg_question_score,
    d.avg_answer_score,
    d.question_views,
    d.favorites,
    d.accepted_questions,
    d.comment_score,
    d.upmods_cast,
    d.downmods_cast,
    d.net_votes_cast,
    d.bounties_started_amt,
    d.bounties_awarded_amt,
    d.links_made,
    d.duplicates_marked,
    d.moderation_touches,
    d.total_badges,
    d.gold_badges,
    d.silver_badges,
    d.bronze_badges,
    d.posts_total,
    d.post_score_total,
    d.post_comment_count,
    d.community_posts,
    d.closed_posts,
    coalesce(d.distinct_tags, d.tag_count_check) as distinct_tags_estimate,
    substring(coalesce(d.tag_list_sample,''), 1, 200) as tag_list_sample_trunc,
    d.avg_post_score_90d,
    d.p90_post_score_all_time,
    d.rank_in_cohort_by_rep,
    d.dense_rank_by_p90_score,
    d.rownum_by_activity,
    d.running_total_post_score_by_activity_time,
    d.avg_rep_per_day_in_cohort,
    d.last_activity_any
from dupe_resolution d
where d.tie_breaker = 1
order by
    d.rank_in_cohort_by_rep,
    d.dense_rank_by_p90_score,
    d.rownum_by_activity
limit 500;