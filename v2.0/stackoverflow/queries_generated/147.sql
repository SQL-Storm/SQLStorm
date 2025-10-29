-- {"query": "147.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3131} 
with recent_posts as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        coalesce(p.answercount, 0) as answercount,
        coalesce(p.commentcount, 0) as commentcount,
        p.closeddate,
        p.communityowneddate,
        p.contentlicense
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_aug as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        u.lastaccessdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        u.upvotes,
        u.downvotes,
        u.views as user_views,
        extract(year from age(current_timestamp, u.creationdate))::int as acct_age_years,
        (u.upvotes - coalesce(u.downvotes,0)) as net_votes
    from users u
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comments,
        sum(greatest(c.score,0)) as nonneg_comment_score,
        max(c.creationdate) as last_comment_at,
        count(*) filter (where c.userid is null) as anon_comments
    from comments c
    group by c.postid
),
dup_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links,
        min(pl.creationdate) as first_link_at
    from postlinks pl
    group by pl.postid
),
tag_expansion as (
    select
        rp.post_id,
        lower(trim(t)) as tag
    from recent_posts rp
    cross join lateral unnest(
        case
            when rp.tags is not null and position('<' in rp.tags) > 0
                then string_to_array(substring(rp.tags, 2, length(rp.tags)-2), '><')
            else array[]::varchar[]
        end
    ) as t
),
tag_stats as (
    select
        te.post_id,
        count(*) as tag_count,
        sum(case when tg.isrequired then 1 else 0 end) as required_tags,
        sum(case when tg.ismoderatoronly then 1 else 0 end) as modonly_tags,
        sum(coalesce(tg.count,0)) as tag_popularity_sum,
        max(coalesce(tg.count,0)) as max_tag_popularity,
        min(coalesce(tg.count,0)) as min_tag_popularity
    from tag_expansion te
    left join tags tg
      on tg.tagname = te.tag
    group by te.post_id
),
post_state as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 12) as last_deleted_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 13) as last_undeleted_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 50) as last_community_bump,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied
    from posthistory ph
    group by ph.postid
),
accepted_info as (
    select
        q.id as question_id,
        q.acceptedanswerid as accepted_id,
        a.owneruserid as accepted_owner,
        a.score as accepted_score,
        a.creationdate as accepted_created,
        q.creationdate as question_created,
        extract(epoch from (a.creationdate - q.creationdate))/3600.0 as hours_to_accept
    from posts q
    left join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
activity_window as (
    select
        rp.post_id,
        rp.creationdate,
        coalesce(v.total_votes,0) as total_votes,
        coalesce(c.comments,0) as comments,
        coalesce(d.duplicate_links,0) as duplicate_links,
        row_number() over (order by rp.creationdate desc, rp.post_id) as rn_desc,
        row_number() over (order by rp.creationdate asc, rp.post_id) as rn_asc,
        rank() over (order by coalesce(v.total_votes,0) desc) as vote_rank,
        dense_rank() over (order by coalesce(c.comments,0) desc) as comment_dense_rank
    from recent_posts rp
    left join votes_agg v on v.postid = rp.post_id
    left join comment_agg c on c.postid = rp.post_id
    left join dup_links d on d.postid = rp.post_id
),
user_activity as (
    select
        rp.owneruserid as user_id,
        count(*) as posts_count,
        avg(coalesce(rp.score,0)) as avg_score,
        sum(coalesce(v.total_votes,0)) as sum_votes,
        count(*) filter (where rp.closeddate is not null) as closed_posts,
        count(*) filter (where rp.communityowneddate is not null) as community_posts,
        max(rp.creationdate) as last_post_created
    from recent_posts rp
    left join votes_agg v on v.postid = rp.post_id
    group by rp.owneruserid
),
quality_score as (
    select
        rp.post_id,
        (
            coalesce(rp.score,0)*3
            + coalesce(v.upvotes,0)*2
            - coalesce(v.downvotes,0)*2
            + least(coalesce(c.nonneg_comment_score,0), 20)
            + greatest(0, 10 - coalesce(ta.tag_count,0))
            + case when rp.viewcount is null then 0 else log(greatest(1, rp.viewcount)) end
            - case when rp.closeddate is not null then 15 else 0 end
            + case when ps.last_reopened_at is not null then 5 else 0 end
            + case when coalesce(d.duplicate_links,0) > 0 then -8 else 0 end
        )::numeric(18,4) as quality_score
    from recent_posts rp
    left join votes_agg v on v.postid = rp.post_id
    left join comment_agg c on c.postid = rp.post_id
    left join tag_stats ta on ta.post_id = rp.post_id
    left join dup_links d on d.postid = rp.post_id
    left join post_state ps on ps.postid = rp.post_id
),
user_rollup as (
    select
        ua.user_id,
        ua.posts_count,
        ua.avg_score,
        ua.sum_votes,
        ua.closed_posts,
        ua.community_posts,
        ua.last_post_created,
        u.displayname,
        u.reputation,
        u.location_norm,
        u.acct_age_years,
        u.net_votes,
        row_number() over (order by ua.sum_votes desc nulls last) as user_vote_rank
    from user_activity ua
    left join user_aug u on u.user_id = ua.user_id
),
question_metrics as (
    select
        rp.post_id,
        case when rp.posttypeid = 1 then 1 else 0 end as is_question,
        coalesce(ai.hours_to_accept, null) as hours_to_accept,
        case
            when rp.posttypeid = 1 and rp.acceptedanswerid is not null then 1
            when rp.posttypeid = 1 then 0
            else null
        end as has_accepted_flag
    from posts rp
    left join accepted_info ai on ai.question_id = rp.id
),
ranked as (
    select
        rp.post_id,
        rp.posttypeid,
        rp.owneruserid,
        rp.creationdate,
        rp.title,
        lower(coalesce(rp.title,'')) like any (array['%how to%','%best way%','%why %']) as title_pattern_flag,
        qs.quality_score,
        aw.vote_rank,
        aw.comment_dense_rank,
        ts.tag_count,
        coalesce(ts.tag_popularity_sum,0) as tag_popularity_sum,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(ca.comments,0) as comments,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        ps.last_closed_at,
        ps.last_reopened_at,
        qm.hours_to_accept,
        qm.has_accepted_flag,
        row_number() over (
            partition by rp.owneruserid
            order by qs.quality_score desc, aw.vote_rank asc, rp.creationdate desc
        ) as rn_per_user
    from recent_posts rp
    left join quality_score qs on qs.post_id = rp.post_id
    left join activity_window aw on aw.post_id = rp.post_id
    left join tag_stats ts on ts.post_id = rp.post_id
    left join votes_agg va on va.postid = rp.post_id
    left join comment_agg ca on ca.postid = rp.post_id
    left join dup_links dl on dl.postid = rp.post_id
    left join post_state ps on ps.postid = rp.post_id
    left join question_metrics qm on qm.post_id = rp.post_id
),
user_top_posts as (
    select r.*
    from ranked r
    where r.rn_per_user <= 3
),
nullness_check as (
    select
        rp.post_id,
        (rp.title is null)::int as title_is_null,
        (rp.tags is null)::int as tags_is_null,
        (rp.closeddate is null)::int as closed_is_null
    from recent_posts rp
),
final_union as (
    select
        'TOP' as bucket,
        utp.post_id,
        utp.owneruserid,
        utp.title,
        utp.quality_score,
        utp.vote_rank,
        utp.comment_dense_rank,
        utp.tag_count,
        utp.tag_popularity_sum,
        utp.upvotes,
        utp.downvotes,
        utp.comments,
        utp.duplicate_links,
        utp.last_closed_at,
        utp.last_reopened_at,
        utp.hours_to_accept,
        utp.has_accepted_flag
    from user_top_posts utp
    union all
    select
        'LOW' as bucket,
        r.post_id,
        r.owneruserid,
        r.title,
        r.quality_score,
        r.vote_rank,
        r.comment_dense_rank,
        r.tag_count,
        r.tag_popularity_sum,
        r.upvotes,
        r.downvotes,
        r.comments,
        r.duplicate_links,
        r.last_closed_at,
        r.last_reopened_at,
        r.hours_to_accept,
        r.has_accepted_flag
    from ranked r
    where r.quality_score < (
        select percentile_disc(0.1) within group (order by quality_score)
        from quality_score
    )
),
location_norm as (
    select
        ur.user_id,
        case
            when position(',' in ur.location_norm) > 0 then trim(split_part(ur.location_norm, ',', 2))
            when position(' ' in ur.location_norm) > 0 then trim(split_part(ur.location_norm, ' ', 2))
            else ur.location_norm
        end as region_guess
    from user_rollup ur
)
select
    fu.bucket,
    fu.post_id,
    fu.title,
    coalesce(ur.displayname, 'Anonymous') as owner_displayname,
    coalesce(ur.reputation, 0) as owner_reputation,
    coalesce(ur.posts_count, 0) as owner_recent_posts,
    coalesce(ur.sum_votes, 0) as owner_recent_votes,
    coalesce(ln.region_guess, 'Unknown') as owner_region,
    fu.quality_score,
    fu.upvotes,
    fu.downvotes,
    fu.comments,
    fu.tag_count,
    fu.tag_popularity_sum,
    fu.duplicate_links,
    fu.last_closed_at,
    fu.last_reopened_at,
    fu.hours_to_accept,
    fu.has_accepted_flag,
    nc.title_is_null,
    nc.tags_is_null,
    nc.closed_is_null,
    case
        when fu.quality_score >= (select avg(quality_score) from quality_score) then 'AboveAvg'
        when fu.quality_score is null then 'Unknown'
        else 'BelowAvg'
    end as quality_bucket_label,
    row_number() over (partition by fu.bucket order by fu.quality_score desc nulls last, fu.upvotes desc, fu.comments desc) as bucket_rownum
from final_union fu
left join user_rollup ur on ur.user_id = fu.owneruserid
left join location_norm ln on ln.user_id = fu.owneruserid
left join nullness_check nc on nc.post_id = fu.post_id
where
    (
        fu.has_accepted_flag is null
        or (fu.has_accepted_flag = 1 and coalesce(fu.hours_to_accept, 99999) <= 168)
        or (fu.has_accepted_flag = 0)
    )
    and (fu.upvotes - fu.downvotes) between -10 and 10000
    and (coalesce(fu.tag_count,0) between 0 and 10)
    and (fu.last_closed_at is null or fu.last_reopened_at is not null or fu.duplicate_links = 0)
order by
    fu.bucket,
    bucket_rownum,
    fu.post_id;