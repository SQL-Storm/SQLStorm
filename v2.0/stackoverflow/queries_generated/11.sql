-- {"query": "11.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2902} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
        width_bucket(u.reputation, 0, 100000, 10) as rep_bucket,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'unknown') order by u.reputation desc, u.id) as rn_loc
    from users u
    where u.creationdate >= (select max(creationdate) - interval '2 years' from users)
),
user_badge_agg as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        count(*) as total_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_posts as (
    select
        p.id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.closeddate,
        p.communityowneddate,
        p.favoritecount
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        a.id,
        a.parentid as question_id,
        a.owneruserid as user_id,
        a.creationdate,
        a.score
    from posts a
    where a.posttypeid = 2
),
answer_stats as (
    select
        q.user_id,
        q.id as question_id,
        count(a.id) as answers_cnt,
        avg(a.score) as avg_answer_score,
        max(a.creationdate) as last_answer_date
    from question_posts q
    left join answers a on a.question_id = q.id
    group by q.user_id, q.id
),
vote_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        sum(case when v.votetypeid in (2,3) then 1 else 0 end) as total_votes,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        min(c.creationdate) as first_comment_date,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
ph_close as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        count(*) filter (where ph.posthistorytypeid in (10,11)) as close_reopen_events
    from posthistory ph
    group by ph.postid
),
dup_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as normal_links,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
tag_explode as (
    select
        q.id as question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from question_posts q
    where q.tags is not null and length(q.tags) > 2
),
tag_popularity as (
    select
        te.question_id,
        avg(t.count) as avg_tag_popularity,
        sum(case when t.ismoderatoronly then 1 else 0 end) as mod_only_tags,
        sum(case when t.isrequired then 1 else 0 end) as required_tags
    from tag_explode te
    left join tags t on lower(t.tagname) = lower(te.tagname)
    group by te.question_id
),
question_metrics as (
    select
        q.id as question_id,
        q.user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        qa.answers_cnt,
        qa.avg_answer_score,
        qa.last_answer_date,
        va.upvotes,
        va.downvotes,
        va.total_votes,
        coalesce(va.bounty_total, 0) as bounty_total,
        ca.comment_count,
        ca.max_comment_score,
        ph.close_events,
        ph.reopen_events,
        ph.first_close_date,
        ph.last_reopen_date,
        dl.duplicate_links,
        dl.normal_links,
        tp.avg_tag_popularity,
        tp.mod_only_tags,
        tp.required_tags,
        case when q.closeddate is not null then 1 else 0 end as is_closed,
        case when q.communityowneddate is not null then 1 else 0 end as is_community
    from question_posts q
    left join answer_stats qa on qa.question_id = q.id
    left join vote_agg va on va.postid = q.id
    left join comment_agg ca on ca.postid = q.id
    left join ph_close ph on ph.postid = q.id
    left join dup_links dl on dl.postid = q.id
    left join tag_popularity tp on tp.question_id = q.id
),
user_activity as (
    select
        qm.user_id,
        count(*) as question_count,
        sum(case when qm.is_closed = 1 then 1 else 0 end) as closed_q_count,
        sum(coalesce(qm.viewcount,0)) as total_views,
        sum(coalesce(qm.score,0)) as total_q_score,
        avg(coalesce(qm.answercount,0)) as avg_answers_per_q,
        sum(coalesce(qm.bounty_total,0)) as total_bounty,
        max(qm.creationdate) as last_q_date,
        percentile_cont(0.5) within group (order by coalesce(qm.viewcount,0)) as median_q_views
    from question_metrics qm
    group by qm.user_id
),
accepted_answers as (
    select
        p.owneruserid as answerer_id,
        count(*) as accepted_count
    from posts q
    join posts p on p.id = q.acceptedanswerid
    where q.posttypeid = 1
    group by p.owneruserid
),
power_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.rep_bucket,
        ua.question_count,
        ua.closed_q_count,
        ua.total_views,
        ua.total_q_score,
        ua.avg_answers_per_q,
        ua.total_bounty,
        aa.accepted_count,
        coalesce(uba.total_badges,0) as total_badges
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join accepted_answers aa on aa.answerer_id = ru.user_id
    left join user_badge_agg uba on uba.userid = ru.user_id
    where ru.rn_loc <= 50
),
ranked_users as (
    select
        pu.*,
        row_number() over (
            order by
                coalesce(pu.total_q_score,0) * 1.0 +
                coalesce(pu.total_views,0) * 0.001 +
                coalesce(pu.accepted_count,0) * 5 +
                coalesce(pu.total_badges,0) * 0.5 +
                coalesce(pu.total_bounty,0) * 0.01 desc,
                pu.reputation desc,
                pu.user_id
        ) as global_rank
    from power_users pu
),
cross_user_compare as (
    select
        a.user_id as user_a,
        b.user_id as user_b,
        abs(coalesce(a.total_q_score,0) - coalesce(b.total_q_score,0)) as score_gap,
        abs(coalesce(a.total_views,0) - coalesce(b.total_views,0)) as view_gap,
        abs(coalesce(a.accepted_count,0) - coalesce(b.accepted_count,0)) as accepted_gap
    from power_users a
    join power_users b on a.user_id < b.user_id
    where abs(coalesce(a.rep_bucket,0) - coalesce(b.rep_bucket,0)) <= 1
),
dense_metrics as (
    select
        qm.user_id,
        count(*) filter (where qm.total_votes >= 10) as q_with_10_votes,
        count(*) filter (where qm.comment_count >= 5) as q_with_5_comments,
        avg(coalesce(qm.avg_answer_score,0)) as avg_ans_score_per_user,
        count(*) filter (where qm.duplicate_links >= 1) as q_with_dup_link
    from question_metrics qm
    group by qm.user_id
),
activity_windows as (
    select
        qm.user_id,
        qm.creationdate::date as q_date,
        count(*) over (partition by qm.user_id order by qm.creationdate range between interval '30 days' preceding and current row) as rolling_30d_qs,
        sum(coalesce(qm.viewcount,0)) over (partition by qm.user_id order by qm.creationdate rows between 10 preceding and current row) as views_last_11_qs
    from question_metrics qm
),
final as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.rep_bucket,
        ru.question_count,
        ru.closed_q_count,
        ru.total_views,
        ru.total_q_score,
        ru.avg_answers_per_q,
        ru.total_bounty,
        ru.accepted_count,
        ru.total_badges,
        r.global_rank,
        dm.q_with_10_votes,
        dm.q_with_5_comments,
        dm.avg_ans_score_per_user,
        dm.q_with_dup_link,
        max(case when aw.rolling_30d_qs >= 3 then 1 else 0 end) as bursty_30d_flag,
        max(case when aw.views_last_11_qs >= 50000 then 1 else 0 end) as highly_viewed_recent_flag
    from ranked_users r
    join power_users ru on ru.user_id = r.user_id
    left join dense_metrics dm on dm.user_id = ru.user_id
    left join activity_windows aw on aw.user_id = ru.user_id
    group by
        ru.user_id, ru.displayname, ru.reputation, ru.location, ru.rep_bucket,
        ru.question_count, ru.closed_q_count, ru.total_views, ru.total_q_score,
        ru.avg_answers_per_q, ru.total_bounty, ru.accepted_count, ru.total_badges,
        r.global_rank
)
select
    f.user_id,
    f.displayname,
    f.reputation,
    f.location,
    f.rep_bucket,
    f.global_rank,
    f.question_count,
    f.closed_q_count,
    f.total_q_score,
    f.total_views,
    round(coalesce(f.avg_answers_per_q,0)::numeric, 3) as avg_answers_per_q,
    f.total_bounty,
    f.accepted_count,
    f.total_badges,
    f.q_with_10_votes,
    f.q_with_5_comments,
    round(coalesce(f.avg_ans_score_per_user,0)::numeric, 3) as avg_ans_score_per_user,
    f.q_with_dup_link,
    f.bursty_30d_flag,
    f.highly_viewed_recent_flag,
    -- Complex predicate-driven classifications
    case
        when coalesce(f.total_q_score,0) >= 1000 and coalesce(f.total_views,0) >= 100000 then 'Elite'
        when coalesce(f.total_q_score,0) >= 300 and coalesce(f.total_views,0) >= 30000 then 'Pro'
        when coalesce(f.total_q_score,0) >= 100 then 'Rising'
        else 'Casual'
    end as tier,
    -- String manipulation and NULL/empty handling
    regexp_replace(coalesce(nullif(trim(f.displayname), ''), 'Anonymous'), '\s+', ' ', 'g') as cleaned_displayname
from final f
where
    -- Complicated predicate mixing NULL logic and expressions
    (coalesce(f.total_q_score, 0) + coalesce(f.total_views, 0) * 0.0005 + coalesce(f.accepted_count,0) * 2) >=
        (select avg(coalesce(total_q_score,0) + coalesce(total_views,0) * 0.0005 + coalesce(accepted_count,0) * 2) from final)
    and (f.bursty_30d_flag = 1 or f.highly_viewed_recent_flag = 1 or f.tier in ('Elite','Pro'))
order by
    f.global_rank
fetch first 200 rows only;