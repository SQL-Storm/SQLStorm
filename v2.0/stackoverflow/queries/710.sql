-- {"query": "710.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2847}
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.owneruserid,
        p.title,
        p.tags,
        p.score,
        p.viewcount,
        p.answercount,
        date_trunc('month', p.creationdate) as month_bucket
    from posts p
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
),
tag_expanded as (
    select
        rp.id as post_id,
        rp.owneruserid,
        rp.month_bucket,
        lower(trim(t_tag)) as tag
    from recent_posts rp,
    lateral (
        select unnest(
            case
                when rp.tags is null then array[]::text[]
                else string_to_array(substring(rp.tags from 2 for greatest(char_length(rp.tags)-2,0)), '><')
            end
        ) as t_tag
    ) u
),
user_basics as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_creation,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm
    from users u
),
user_activity as (
    select
        ua.owneruserid as user_id,
        count(case when ua.posttypeid = 1 then 1 end) as q_cnt,
        count(case when ua.posttypeid = 2 then 1 end) as a_cnt,
        sum(ua.score) as total_score,
        sum(ua.viewcount) as total_views,
        avg(nullif(ua.answercount,0)) as avg_answers_per_q,
        min(ua.creationdate) as first_post_at,
        max(ua.creationdate) as last_post_at
    from recent_posts ua
    group by ua.owneruserid
),
user_comment_summary as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(c.score) as comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
    group by c.userid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(case when b.class = 1 then 1 end) as gold_badges,
        count(case when b.class = 2 then 1 end) as silver_badges,
        count(case when b.class = 3 then 1 end) as bronze_badges,
        max(b.date) as last_badge_at
    from badges b
    where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
    group by b.userid
),
dup_links as (
    select
        pl.postid as duplicate_of,
        count(case when pl.linktypeid = 3 then 1 end) as dup_mark_count
    from postlinks pl
    where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
    group by pl.postid
),
close_events as (
    select
        ph.postid,
        count(case when ph.posthistorytypeid = 10 then 1 end) as close_votes,
        count(case when ph.posthistorytypeid = 11 then 1 end) as reopen_votes,
        max(case when ph.posthistorytypeid in (10,11) then ph.creationdate end) as last_close_or_reopen
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
    group by ph.postid
),
post_quality as (
    select
        rp.id as post_id,
        rp.owneruserid as user_id,
        rp.month_bucket,
        rp.score,
        rp.viewcount,
        rp.answercount,
        coalesce(cl.close_votes,0) as close_votes,
        coalesce(cl.reopen_votes,0) as reopen_votes,
        coalesce(dl.dup_mark_count,0) as dup_marks,
        (coalesce(rp.score,0) * 3
         + coalesce(rp.viewcount,0) * 0.01
         + coalesce(rp.answercount,0) * 2
         - coalesce(cl.close_votes,0) * 5
         - coalesce(dl.dup_mark_count,0) * 4) as quality_score
    from recent_posts rp
    left join close_events cl on cl.postid = rp.id
    left join dup_links dl on dl.duplicate_of = rp.id
),
user_monthly as (
    select
        pq.user_id,
        pq.month_bucket,
        count(*) as posts_in_month,
        avg(pq.quality_score) as avg_quality_in_month,
        sum(case when pq.score > 0 then 1 else 0 end) as pos_scored_posts,
        sum(case when pq.score < 0 then 1 else 0 end) as neg_scored_posts
    from post_quality pq
    group by pq.user_id, pq.month_bucket
),
tag_rollup as (
    select
        te.owneruserid as user_id,
        te.month_bucket,
        te.tag,
        count(*) as tag_posts,
        row_number() over (partition by te.owneruserid, te.month_bucket order by count(*) desc, te.tag) as tag_rank
    from tag_expanded te
    group by te.owneruserid, te.month_bucket, te.tag
),
top_tag_per_month as (
    select user_id, month_bucket, tag as top_tag, tag_posts
    from tag_rollup
    where tag_rank = 1
),
vote_agg as (
    select
        v.postid,
        count(case when v.votetypeid = 2 then 1 end) as upvotes,
        count(case when v.votetypeid = 3 then 1 end) as downvotes,
        count(case when v.votetypeid = 5 then 1 end) as favorites,
        max(v.creationdate) as last_vote_at
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
    group by v.postid
),
user_vote_summary as (
    select
        rp.owneruserid as user_id,
        sum(va.upvotes) as upvotes,
        sum(va.downvotes) as downvotes,
        sum(va.favorites) as favorites,
        max(va.last_vote_at) as last_vote_at
    from recent_posts rp
    left join vote_agg va on va.postid = rp.id
    group by rp.owneruserid
),
activity_union as (
    select
        ub.user_id,
        date_trunc('month', ub.user_creation) as month_bucket,
        'signup' as kind,
        cast(1 as bigint) as qty
    from user_basics ub
    union all
    select
        ua.user_id,
        date_trunc('month', ua.first_post_at),
        'first_post',
        cast(1 as bigint)
    from user_activity ua
    union all
    select
        ucs.user_id,
        date_trunc('month', ucs.last_comment_at),
        'comment_activity',
        cast(ucs.comment_count as bigint)
    from user_comment_summary ucs
),
activity_pivot as (
    select
        user_id,
        month_bucket,
        sum(case when kind = 'signup' then qty else 0 end) as signup_events,
        sum(case when kind = 'first_post' then qty else 0 end) as first_post_events,
        sum(case when kind = 'comment_activity' then qty else 0 end) as comment_events
    from activity_union
    group by user_id, month_bucket
),
user_rankings as (
    select
        ub.user_id,
        ub.displayname,
        ub.location_norm,
        ub.reputation,
        ua.total_score,
        uvs.upvotes,
        uvs.downvotes,
        uvs.favorites,
        dense_rank() over (order by coalesce(ua.total_score,0) desc, coalesce(uvs.upvotes,0) desc, ub.reputation desc) as perf_rank
    from user_basics ub
    left join user_activity ua on ua.user_id = ub.user_id
    left join user_vote_summary uvs on uvs.user_id = ub.user_id
),
null_guard as (
    select
        ur.user_id,
        coalesce(ur.displayname, ('user#' || cast(ur.user_id as varchar))) as displayname_safe,
        coalesce(nullif(regexp_replace(ur.location_norm, '\s+', ' ', 'g'), ''), 'Unknown') as location_safe,
        coalesce(ur.reputation, 0) as reputation_safe,
        coalesce(ur.perf_rank, 999999) as perf_rank_safe
    from user_rankings ur
),
user_month_enriched as (
    select
        um.user_id,
        um.month_bucket,
        um.posts_in_month,
        um.avg_quality_in_month,
        um.pos_scored_posts,
        um.neg_scored_posts,
        coalesce(tt.top_tag, 'none') as top_tag,
        coalesce(tt.tag_posts, 0) as top_tag_posts,
        coalesce(ap.signup_events,0) as signup_events,
        coalesce(ap.first_post_events,0) as first_post_events,
        coalesce(ap.comment_events,0) as comment_events
    from user_monthly um
    left join top_tag_per_month tt
        on tt.user_id = um.user_id
       and tt.month_bucket = um.month_bucket
    left join activity_pivot ap
        on ap.user_id = um.user_id
       and ap.month_bucket = um.month_bucket
),
seasonality as (
    select
        ume.user_id,
        cast(extract(month from ume.month_bucket) as integer) as month_num,
        avg(ume.posts_in_month) as avg_posts,
        avg(ume.avg_quality_in_month) as avg_quality
    from user_month_enriched ume
    group by ume.user_id, cast(extract(month from ume.month_bucket) as integer)
),
outlier_flags as (
    select
        ume.user_id,
        ume.month_bucket,
        ume.posts_in_month,
        ume.avg_quality_in_month,
        case
            when ume.posts_in_month > 0 and ume.avg_quality_in_month / nullif(ume.posts_in_month,0) > 5 then 1
            else 0
        end as high_quality_density,
        case
            when ume.neg_scored_posts > ume.pos_scored_posts then 1 else 0
        end as more_neg_than_pos
    from user_month_enriched ume
),
final_scores as (
    select
        ume.user_id,
        ume.month_bucket,
        nr.displayname_safe,
        nr.location_safe,
        nr.reputation_safe,
        nr.perf_rank_safe,
        ume.posts_in_month,
        ume.avg_quality_in_month,
        ume.top_tag,
        ume.top_tag_posts,
        ume.signup_events,
        ume.first_post_events,
        ume.comment_events,
        coalesce(of.high_quality_density,0) as high_quality_density,
        coalesce(of.more_neg_than_pos,0) as more_neg_than_pos,
        round(
            greatest(0,
                0.40 * coalesce(ume.avg_quality_in_month,0)
              + 0.25 * coalesce(ume.posts_in_month,0)
              + 0.15 * coalesce(ume.top_tag_posts,0)
              + 0.10 * coalesce(ume.comment_events,0) / 10.0
              + 0.10 * (case when of.high_quality_density = 1 then 5 else 0 end)
            ), 2
        ) as monthly_perf_index
    from user_month_enriched ume
    join null_guard nr on nr.user_id = ume.user_id
    left join outlier_flags of on of.user_id = ume.user_id and of.month_bucket = ume.month_bucket
),
leaderboard as (
    select
        fs.*,
        row_number() over (
            partition by fs.month_bucket
            order by fs.monthly_perf_index desc, fs.reputation_safe desc, fs.perf_rank_safe
        ) as rank_in_month
    from final_scores fs
)
select
    cast(l.month_bucket as date) as month,
    l.rank_in_month,
    l.user_id,
    l.displayname_safe as displayname,
    l.location_safe as location,
    l.reputation_safe as reputation,
    l.posts_in_month,
    l.avg_quality_in_month,
    l.top_tag,
    l.top_tag_posts,
    l.signup_events,
    l.first_post_events,
    l.comment_events,
    l.high_quality_density,
    l.more_neg_than_pos,
    l.monthly_perf_index,
    coalesce((
        select extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - greatest(
            coalesce(ua.last_post_at, timestamp '1970-01-01 00:00:00'),
            coalesce(ucs.last_comment_at, timestamp '1970-01-01 00:00:00'),
            coalesce(uvs.last_vote_at, timestamp '1970-01-01 00:00:00'),
            coalesce(ub.last_badge_at, timestamp '1970-01-01 00:00:00')
        ))) / 86400.0
        from user_activity ua
        left join user_comment_summary ucs on ucs.user_id = ua.user_id
        left join user_vote_summary uvs on uvs.user_id = ua.user_id
        left join user_badges ub on ub.user_id = ua.user_id
        where ua.user_id = l.user_id
    ), null) as days_since_last_activity
from leaderboard l
where l.rank_in_month <= 20
order by l.month_bucket desc, l.rank_in_month asc;