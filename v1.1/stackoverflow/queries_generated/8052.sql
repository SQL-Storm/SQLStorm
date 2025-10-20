-- {"query": "8052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3572} 
with params as (
    select
        365 as days_back,
        50 as min_rep,
        0.05 as heavy_editor_top_pct
),
recent_posts as (
    select p.*
    from Posts p
    cross join params
    where p.CreationDate >= now() - (interval '1 day' * params.days_back)
      and p.PostTypeId in (1,2)
),
-- Explode tags into rows
tags_expanded as (
    select
        p.Id as PostId,
        lower(trim(t)) as tag
    from recent_posts p
    cross join lateral unnest(
        case
            when p.Tags is null then array[]::varchar[]
            else string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><')
        end
    ) as t
),
-- Aggregate votes per post with windowed ranks
post_votes as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as bounty_started,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as bounty_awarded,
        count(*) as vote_events,
        max(v.CreationDate) as last_vote_date
    from Votes v
    join recent_posts rp on rp.Id = v.PostId
    group by v.PostId
),
-- Comments stats with correlated filtering for early comments
comment_stats as (
    select
        c.PostId,
        count(*) as comment_count,
        avg(coalesce(nullif(c.Score,0), 0)) as avg_comment_score_incl_zero,
        sum(case when c.Score > 0 then 1 else 0 end) as positive_comments,
        min(c.CreationDate) as first_comment_at,
        sum(case when c.CreationDate <= (select CreationDate + interval '1 day' from Posts p where p.Id = c.PostId) then 1 else 0 end) as comments_first_24h
    from Comments c
    join recent_posts rp on rp.Id = c.PostId
    group by c.PostId
),
-- Edit intensity metrics from PostHistory
edit_events as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as edit_count,
        count(*) filter (where ph.PostHistoryTypeId = 24) as suggested_edits_applied,
        count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36)) as mod_state_changes,
        min(ph.CreationDate) as first_edit_at,
        max(ph.CreationDate) as last_edit_at
    from PostHistory ph
    join recent_posts rp on rp.Id = ph.PostId
    group by ph.PostId
),
-- Linkage: duplicates and related links
linkage as (
    select
        pl.PostId,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as dup_links,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as related_links,
        count(*) as total_links,
        count(distinct pl.RelatedPostId) as distinct_link_targets
    from PostLinks pl
    join recent_posts rp on rp.Id = pl.PostId
    group by pl.PostId
),
-- Owner signals
owner_signals as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        date_part('day', now() - u.CreationDate) as account_age_days
    from Users u
),
-- Per-post owner joined with null-safe defaults
post_owner as (
    select
        p.Id as PostId,
        coalesce(u.Reputation, 0) as owner_rep,
        coalesce(u.UpVotes, 0) as owner_up,
        coalesce(u.DownVotes, 0) as owner_down,
        coalesce(u.Views, 0) as owner_views,
        coalesce(os.account_age_days, 0) as owner_age_days,
        case when u.Id is null then 1 else 0 end as is_owner_deleted
    from recent_posts p
    left join Users u on u.Id = p.OwnerUserId
    left join owner_signals os on os.UserId = u.Id
),
-- Tag popularity snapshot
tag_pop as (
    select
        te.tag,
        count(*) as recent_tag_usage,
        sum(case when rp.PostTypeId = 1 then 1 else 0 end) as recent_question_tag_usage
    from tags_expanded te
    join recent_posts rp on rp.Id = te.PostId
    group by te.tag
),
-- Post-level tag aggregates
post_tag_features as (
    select
        te.PostId,
        count(*) as tag_count,
        string_agg(te.tag, ',' order by te.tag) as tag_list_csv,
        max(tp.recent_tag_usage) as max_tag_recent_usage,
        avg(tp.recent_question_tag_usage::numeric) as avg_tag_recent_q_usage
    from tags_expanded te
    left join tag_pop tp on tp.tag = te.tag
    group by te.PostId
),
-- Rank posts by edit intensity per owner to find "heavy editors"
owner_edit_intensity as (
    select
        p.OwnerUserId as UserId,
        p.Id as PostId,
        coalesce(ee.edit_count, 0) as edit_count,
        row_number() over (partition by p.OwnerUserId order by coalesce(ee.edit_count,0) desc, p.Id) as rn_by_owner,
        count(*) over (partition by p.OwnerUserId) as owner_post_count
    from recent_posts p
    left join edit_events ee on ee.PostId = p.Id
),
heavy_editors as (
    select
        oei.UserId,
        percentile_disc(heavy_editor_top_pct) within group (order by oei.edit_count desc nulls last) as top_cutoff
    from owner_edit_intensity oei
    join params on true
    where oei.UserId is not null
    group by oei.UserId
),
-- Compute engagement score with various expressions, null handling, and conditional weighting
post_engagement as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        coalesce(pv.upvotes,0) as upvotes,
        coalesce(pv.downvotes,0) as downvotes,
        coalesce(pv.favorites,0) as favorites,
        coalesce(pv.bounty_started,0) as bounty_started,
        coalesce(pv.bounty_awarded,0) as bounty_awarded,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(cs.avg_comment_score_incl_zero,0) as avg_comment_score,
        coalesce(cs.comments_first_24h,0) as comments_first_24h,
        coalesce(le.total_links,0) as total_links,
        coalesce(le.dup_links,0) as dup_links,
        coalesce(ptf.tag_count,0) as tag_count,
        ptf.tag_list_csv,
        po.owner_rep,
        po.owner_up,
        po.owner_down,
        po.owner_views,
        po.owner_age_days,
        po.is_owner_deleted,
        coalesce(ee.edit_count,0) as edit_count,
        coalesce(ee.suggested_edits_applied,0) as suggested_edits_applied,
        coalesce(ee.mod_state_changes,0) as mod_state_changes,
        case when ee.first_edit_at is null then 0 else extract(epoch from (coalesce(ee.last_edit_at, now()) - ee.first_edit_at)) end as edit_span_secs,
        coalesce(pv.vote_events,0) as vote_events,
        -- Composite engagement score with mixed numeric/string/null logic
        (
            greatest(coalesce(p.Score,0), 0)
            + 0.6 * coalesce(pv.upvotes,0)
            - 0.4 * coalesce(pv.downvotes,0)
            + 0.2 * coalesce(cs.comment_count,0)
            + case when p.PostTypeId = 1 then 1.0 else 0.5 end * ln(1 + coalesce(p.ViewCount,0))
            + case when coalesce(le.dup_links,0) > 0 then -2 else 0 end
            + case when coalesce(ee.edit_count,0) > 0 then least(ee.edit_count, 10) * 0.3 else 0 end
            + case when coalesce(po.owner_rep,0) >= (select min_rep from params) then 0.5 else 0 end
        )::numeric(18,4) as engagement_score
    from recent_posts p
    left join post_votes pv on pv.PostId = p.Id
    left join comment_stats cs on cs.PostId = p.Id
    left join linkage le on le.PostId = p.Id
    left join post_tag_features ptf on ptf.PostId = p.Id
    left join post_owner po on po.PostId = p.Id
    left join edit_events ee on ee.PostId = p.Id
),
-- Determine if post owner qualifies as a heavy editor based on their cutoff
owner_heavy_flag as (
    select
        pei.PostId,
        case
            when p.OwnerUserId is null then 0
            when coalesce(ee.edit_count,0) >= coalesce(he.top_cutoff, 0) then 1
            else 0
        end as is_heavy_editor_by_owner
    from post_engagement pei
    join Posts p on p.Id = pei.PostId
    left join edit_events ee on ee.PostId = pei.PostId
    left join heavy_editors he on he.UserId = p.OwnerUserId
),
-- Closed/duplicate status via PostHistory and PostLinks
closure as (
    select
        p.Id as PostId,
        max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as was_closed,
        max(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.PostHistoryTypeId in (35,36) then 1 else 0 end) as was_migrated,
        max(case when pl.LinkTypeId = 3 then 1 else 0 end) as is_marked_duplicate
    from recent_posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    group by p.Id
),
-- Windowed ranks across multiple dimensions
ranked as (
    select
        pei.*,
        c.was_closed,
        c.was_reopened,
        c.was_migrated,
        c.is_marked_duplicate,
        ohf.is_heavy_editor_by_owner,
        row_number() over (order by pei.engagement_score desc, pei.vote_events desc, pei.ViewCount desc, pei.PostId desc) as rn_global,
        row_number() over (partition by pei.PostTypeId order by pei.engagement_score desc, pei.vote_events desc) as rn_by_type,
        rank() over (order by coalesce(pei.dup_links,0) desc, coalesce(pei.mod_state_changes,0) desc) as r_dup_mod,
        dense_rank() over (order by coalesce(pei.owner_rep,0) desc) as r_owner_rep_dense,
        percent_rank() over (order by pei.engagement_score) as pr_engagement,
        cume_dist() over (order by pei.engagement_score) as cd_engagement
    from post_engagement pei
    join closure c on c.PostId = pei.PostId
    left join owner_heavy_flag ohf on ohf.PostId = pei.PostId
),
-- Construct a human-ish label from multiple attributes with string ops and null logic
labels as (
    select
        r.PostId,
        (
            coalesce(
                case when r.PostTypeId = 1 then 'Q' when r.PostTypeId = 2 then 'A' else 'P' end
                || '#' || r.PostId::varchar
                || ' [' || coalesce(
                    (select left(coalesce(Title,''), 40) from Posts p where p.Id = r.PostId),
                    'untitled'
                ) || ']'
                , 'unknown'
            )
        ) as post_label,
        coalesce((select OwnerDisplayName from Posts p where p.Id = r.PostId), 'anon') as owner_name_fallback
    from ranked r
),
-- Use set operators to combine top by different criteria
top_by_views as (
    select r.PostId from ranked r where r.ViewCount is not null
    order by r.ViewCount desc nulls last
    limit 50
),
top_by_score as (
    select r.PostId from ranked r where r.Score is not null
    order by r.Score desc nulls last
    limit 50
),
top_union as (
    select PostId from top_by_views
    union
    select PostId from top_by_score
),
-- Final selection with complex predicates and calculated fields
final as (
    select
        r.*,
        l.post_label,
        l.owner_name_fallback,
        case
            when r.was_closed = 1 and r.was_reopened = 1 then 'reopened'
            when r.was_closed = 1 then 'closed'
            when r.is_marked_duplicate = 1 then 'duplicate'
            else 'open'
        end as moderation_state,
        case
            when r.tag_count = 0 then 'untagged'
            when position('python' in coalesce(r.tag_list_csv,'')) > 0 then 'pythonish'
            when position('java' in coalesce(r.tag_list_csv,'')) > 0 then 'javaish'
            else 'other'
        end as coarse_tag_bucket,
        (r.upvotes - r.downvotes) as net_votes,
        nullif(r.favorites,0) as favorites_nullable,
        case when r.is_heavy_editor_by_owner = 1 then 'heavy_editor' else 'normal_editor' end as owner_edit_class
    from ranked r
    join labels l on l.PostId = r.PostId
    where
        -- Complicated predicate combining engagement, moderation, and user signals
        (
            (r.engagement_score > 5 and r.ViewCount > 100)
            or (r.engagement_score > 2 and r.owner_rep >= (select min_rep from params))
            or (r.vote_events > 20 and r.PostTypeId = 1)
        )
        and not (r.was_migrated = 1 and r.is_marked_duplicate = 1)
        and (r.owner_age_days is null or r.owner_age_days >= 0)
)
select
    f.PostId,
    f.post_label,
    f.owner_name_fallback as owner_name,
    f.PostTypeId,
    f.moderation_state,
    f.coarse_tag_bucket,
    f.tag_count,
    f.tag_list_csv,
    f.Score,
    f.ViewCount,
    f.upvotes,
    f.downvotes,
    f.net_votes,
    f.favorites_nullable,
    f.bounty_started,
    f.bounty_awarded,
    f.comment_count,
    f.avg_comment_score,
    f.comments_first_24h,
    f.total_links,
    f.dup_links,
    f.edit_count,
    f.suggested_edits_applied,
    f.mod_state_changes,
    f.edit_span_secs,
    f.owner_rep,
    f.owner_up,
    f.owner_down,
    f.owner_views,
    f.owner_age_days,
    f.is_owner_deleted,
    f.is_heavy_editor_by_owner,
    f.engagement_score,
    f.rn_global,
    f.rn_by_type,
    f.r_dup_mod,
    f.r_owner_rep_dense,
    f.pr_engagement,
    f.cd_engagement,
    case when f.PostId in (select PostId from top_union) then 1 else 0 end as is_top_union
from final f
order by f.engagement_score desc, f.rn_by_type, f.PostId
limit 200;