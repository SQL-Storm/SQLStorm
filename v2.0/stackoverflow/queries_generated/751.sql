-- {"query": "751.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3709} 
with
-- recent active users with rank by activity and reputation buckets
recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        width_bucket(u.reputation, 0, 100000, 5) as rep_bucket,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by greatest(u.lastaccessdate, u.creationdate) desc, u.reputation desc, u.id) as rn_loc_activity
    from users u
    where u.creationdate >= (select max(p.creationdate) from posts p where p.creationdate is not null) - interval '5 years'
),
-- posts in the last N years with tag array and quality metrics
recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.title,
        p.tags,
        string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_array,
        case when p.closeddate is null then 0 else 1 end as is_closed,
        case when p.acceptedanswerid is null then 0 else 1 end as has_accepted,
        coalesce(p.viewcount,0) + coalesce(p.score,0) * 100 + coalesce(p.answercount,0) * 50 as engagement_score
    from posts p
    where p.creationdate >= (select max(ph.creationdate) from posthistory ph where ph.creationdate is not null) - interval '3 years'
      and p.posttypeid in (1,2)
),
-- explode tags
post_tags as (
    select rp.id as post_id, unnest(rp.tag_array) as tagname
    from recent_posts rp
    where rp.posttypeid = 1
),
-- tag popularity and select top tags
top_tags as (
    select pt.tagname, count(*) as q_count
    from post_tags pt
    group by pt.tagname
    having count(*) >= 50
),
-- compute user activity aggregates per tag
user_tag_stats as (
    select
        rp.owneruserid as user_id,
        pt.tagname,
        count(*) filter (where rp.posttypeid = 1) as q_count,
        count(*) filter (where rp.posttypeid = 2) as a_count,
        sum(rp.score) as total_score,
        avg(nullif(rp.score,0)) as avg_nonzero_score,
        avg(rp.score::numeric) as avg_score,
        sum(case when rp.has_accepted = 1 and rp.posttypeid = 2 then 1 else 0 end) as accepted_answers,
        sum(rp.engagement_score) as engagement_sum
    from recent_posts rp
    join post_tags pt on pt.post_id = rp.id and rp.posttypeid = 1
    group by rp.owneruserid, pt.tagname
),
-- votes aggregation for recent posts
post_votes as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    where v.creationdate >= (select max(p.creationdate) from posts p where p.creationdate is not null) - interval '3 years'
    group by v.postid
),
-- latest edit and close events per post
post_events as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (11)) as last_reopen_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (50)) as last_comm_bump
    from posthistory ph
    where ph.creationdate >= (select max(p.creationdate) from posts p where p.creationdate is not null) - interval '3 years'
    group by ph.postid
),
-- duplicate relationships with link types
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate,
        lt.name as link_type
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    where pl.linktypeid = 3
),
-- choose interesting users: active, with badges and mixed vote profile
interesting_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.location_norm,
        ru.rep_bucket,
        count(distinct b.id) as badge_count,
        sum(case when b.class = 1 then 1 else 0 end) as golds,
        sum(case when b.class = 2 then 1 else 0 end) as silvers,
        sum(case when b.class = 3 then 1 else 0 end) as bronzes,
        row_number() over (partition by ru.rep_bucket order by count(distinct b.id) desc nulls last, ru.rn_loc_activity) as rn_rep_badges
    from recent_users ru
    left join badges b on b.userid = ru.user_id and b.date >= ru.creationdate
    group by ru.user_id, ru.displayname, ru.location_norm, ru.rep_bucket, ru.rn_loc_activity
),
-- per-user aggregate votes and comments interaction
user_interactions as (
    select
        u.id as user_id,
        count(distinct c.id) as comment_count,
        sum(c.score) as comment_score,
        count(distinct v.id) filter (where v.votetypeid = 2) as cast_upvotes,
        count(distinct v.id) filter (where v.votetypeid = 3) as cast_downvotes
    from users u
    left join comments c on c.userid = u.id and c.creationdate >= u.creationdate
    left join votes v on v.userid = u.id and v.creationdate >= u.creationdate
    group by u.id
),
-- synthesize per-user, per-tag quality using window functions
user_tag_quality as (
    select
        i.user_id,
        i.displayname,
        i.location_norm,
        i.rep_bucket,
        uts.tagname,
        uts.q_count,
        uts.a_count,
        uts.total_score,
        uts.avg_score,
        uts.avg_nonzero_score,
        uts.accepted_answers,
        uts.engagement_sum,
        sum(uts.total_score) over (partition by i.user_id) as user_total_score,
        rank() over (partition by i.user_id order by uts.total_score desc nulls last, uts.engagement_sum desc nulls last) as tag_rank_by_score
    from interesting_users i
    join user_tag_stats uts on uts.user_id = i.user_id
    join top_tags tt on tt.tagname = uts.tagname
    where i.rn_rep_badges <= 200
),
-- bring posts joined with votes and events
post_facts as (
    select
        rp.id as post_id,
        rp.posttypeid,
        rp.owneruserid as user_id,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.answercount,
        rp.commentcount,
        rp.title,
        rp.tags,
        rp.is_closed,
        rp.has_accepted,
        rp.engagement_score,
        pv.upvotes,
        pv.downvotes,
        pv.favorites,
        pv.bounty_started,
        pv.bounty_awarded,
        pe.last_edit_date,
        pe.last_close_date,
        pe.last_reopen_date,
        pe.last_comm_bump
    from recent_posts rp
    left join post_votes pv on pv.postid = rp.id
    left join post_events pe on pe.postid = rp.id
),
-- correlate duplicate info and accepted answers presence
dup_enriched as (
    select
        pf.post_id,
        case when dl.dup_post_id is not null then 1 else 0 end as is_duplicate,
        dl.original_post_id,
        dl.creationdate as dup_mark_date
    from post_facts pf
    left join dup_links dl on dl.dup_post_id = pf.post_id
),
-- compute per-user rolling activity windows
user_post_windows as (
    select
        pf.user_id,
        pf.post_id,
        pf.creationdate,
        count(*) over (partition by pf.user_id order by pf.creationdate rows between 30 preceding and current row) as posts_last_31_rows,
        sum(pf.score) over (partition by pf.user_id order by pf.creationdate rows between 30 preceding and current row) as score_last_31_rows,
        avg(pf.score) over (partition by pf.user_id order by pf.creationdate rows between unbounded preceding and current row) as running_avg_score
    from post_facts pf
),
-- identify "bursts" of activity by comparing rolling counts
user_bursts as (
    select
        upw.user_id,
        upw.post_id,
        upw.creationdate,
        upw.posts_last_31_rows,
        upw.score_last_31_rows,
        upw.running_avg_score,
        case when upw.posts_last_31_rows >= 10 then 1 else 0 end as is_burst
    from user_post_windows upw
),
-- find comment sentiment proxies via string ops
comment_signals as (
    select
        c.postid,
        count(*) as comments_total,
        sum(case when position('thanks' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end) as thanks_count,
        sum(case when position('why' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end) as why_count,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comments
    from comments c
    where c.creationdate >= (select max(p.creationdate) from posts p where p.creationdate is not null) - interval '3 years'
    group by c.postid
),
-- combine everything per post
post_enriched as (
    select
        pf.*,
        de.is_duplicate,
        de.original_post_id,
        de.dup_mark_date,
        coalesce(cs.comments_total,0) as comments_total,
        coalesce(cs.thanks_count,0) as thanks_count,
        coalesce(cs.why_count,0) as why_count,
        coalesce(cs.pos_comments,0) as pos_comments
    from post_facts pf
    left join dup_enriched de on de.post_id = pf.post_id
    left join comment_signals cs on cs.postid = pf.post_id
),
-- summarize per user and tag across posts
user_tag_post_summary as (
    select
        utq.user_id,
        utq.tagname,
        count(distinct pe.post_id) as posts_with_tag,
        sum(pe.score) as sum_score,
        avg(pe.score::numeric) as avg_score,
        sum(pe.viewcount) as sum_views,
        sum(pe.answercount) as sum_answers,
        sum(pe.favorites) as sum_favorites,
        sum(pe.upvotes) as sum_upvotes,
        sum(pe.downvotes) as sum_downvotes,
        sum(pe.is_closed) as closed_posts,
        sum(case when pe.is_closed = 1 and pe.last_reopen_date is not null then 1 else 0 end) as closed_then_reopened,
        sum(case when pe.has_accepted = 1 and pe.posttypeid = 2 then 1 else 0 end) as accepted_answers_by_user,
        sum(pe.engagement_score) as engagement_total,
        sum(pe.comments_total) as comments_total,
        sum(pe.thanks_count) as thanks_total,
        sum(pe.why_count) as why_total,
        max(pe.creationdate) as last_post_date
    from user_tag_quality utq
    join post_enriched pe on pe.user_id = utq.user_id
    join post_tags pt on pt.post_id = pe.post_id and pt.tagname = utq.tagname
    group by utq.user_id, utq.tagname
),
-- percentile ranks and z-scores across users within tag
tag_peer_stats as (
    select
        utps.*,
        percentile_cont(0.5) within group (order by utps.engagement_total) over (partition by utps.tagname) as tag_engagement_median,
        avg(utps.engagement_total::numeric) over (partition by utps.tagname) as tag_engagement_avg,
        stddev_pop(utps.engagement_total::numeric) over (partition by utps.tagname) as tag_engagement_stddev,
        rank() over (partition by utps.tagname order by utps.sum_score desc nulls last) as tag_rank_by_score,
        cume_dist() over (partition by utps.tagname order by utps.engagement_total) as engagement_cume_dist
    from user_tag_post_summary utps
),
-- final scoring with null-safe handling
final_scores as (
    select
        tps.user_id,
        tps.tagname,
        tps.posts_with_tag,
        tps.sum_score,
        tps.avg_score,
        tps.sum_views,
        tps.sum_answers,
        tps.sum_favorites,
        tps.sum_upvotes,
        tps.sum_downvotes,
        tps.closed_posts,
        tps.closed_then_reopened,
        tps.accepted_answers_by_user,
        tps.comments_total,
        tps.thanks_total,
        tps.why_total,
        tps.last_post_date,
        tps.tag_engagement_median,
        tps.tag_engagement_avg,
        tps.tag_engagement_stddev,
        tps.tag_rank_by_score,
        tps.engagement_cume_dist,
        case
            when coalesce(tps.tag_engagement_stddev,0) = 0 then null
            else (tps.engagement_total - tps.tag_engagement_avg) / nullif(tps.tag_engagement_stddev,0)
        end as engagement_z,
        -- composite score blending normalized metrics
        (
            coalesce((tps.sum_score)::numeric,0) * 1.0 +
            coalesce((tps.sum_upvotes - tps.sum_downvotes)::numeric,0) * 0.75 +
            coalesce((tps.sum_favorites)::numeric,0) * 0.5 +
            coalesce((tps.accepted_answers_by_user)::numeric,0) * 2.0 +
            coalesce((tps.thanks_total - tps.why_total)::numeric,0) * 0.25 +
            coalesce((1000 * (1 - tps.engagement_cume_dist))::numeric,0)
        ) as composite_score
    from tag_peer_stats tps
),
-- pick top tag per user based on composite score
top_tag_per_user as (
    select
        fs.*,
        row_number() over (partition by fs.user_id order by fs.composite_score desc nulls last, fs.posts_with_tag desc, fs.sum_views desc) as rn
    from final_scores fs
)
select
    u.id as user_id,
    coalesce(u.displayname, '(anonymous)') as displayname,
    ir.location_norm,
    ir.rep_bucket,
    tpu.tagname as best_tag,
    tpu.posts_with_tag,
    tpu.sum_score,
    round(coalesce(tpu.avg_score,0), 2) as avg_score,
    tpu.sum_views,
    tpu.sum_answers,
    tpu.sum_favorites,
    tpu.sum_upvotes,
    tpu.sum_downvotes,
    tpu.closed_posts,
    tpu.closed_then_reopened,
    tpu.accepted_answers_by_user,
    tpu.comments_total,
    tpu.thanks_total,
    tpu.why_total,
    tpu.tag_rank_by_score,
    round(coalesce(tpu.engagement_z,0), 3) as engagement_z,
    round(tpu.composite_score, 2) as composite_score,
    ui.comment_count as user_comment_count,
    ui.comment_score as user_comment_score,
    ui.cast_upvotes as user_cast_upvotes,
    ui.cast_downvotes as user_cast_downvotes,
    u.reputation,
    u.creationdate,
    u.lastaccessdate
from top_tag_per_user tpu
join users u on u.id = tpu.user_id
join interesting_users ir on ir.user_id = u.id
left join user_interactions ui on ui.user_id = u.id
where tpu.rn = 1
order by tpu.composite_score desc nulls last, tpu.posts_with_tag desc, u.reputation desc
limit 200;