-- {"query": "2583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1141} 
with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate) as PostRank
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
    union all
    select
        p2.Id,
        p2.PostTypeId,
        p2.CreationDate,
        p2.Score,
        p2.ViewCount,
        p2.OwnerUserId,
        p2.Tags,
        r.PostRank + 1
    from Posts p2
    inner join RecursiveCTE r on p2.OwnerUserId = r.OwnerUserId and p2.CreationDate > r.CreationDate
    where p2.PostTypeId in (1, 2)
)
, UserBadgeStats AS (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        bool_or(b.TagBased = 1) as HasTagBadges
    from Badges b
    group by b.UserId
)
, LatestPostHistory AS (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11, 12, 13)
)
, PostVoteSummary AS (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Votes v
    group by v.PostId
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ub.TotalBadges,
    ub.GoldBadges, 
    ub.SilverBadges, 
    ub.BronzeBadges,
    ub.HasTagBadges,
    p.Id as PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    coalesce(pvs.UpVotes, 0) as PostUpVotes,
    coalesce(pvs.DownVotes, 0) as PostDownVotes,
    coalesce(pvs.TotalBounty, 0) as PostTotalBounty,
    ph.Comment as CloseReason,
    row_number() over (partition by u.Id order by p.Score desc nulls last, p.ViewCount desc nulls last) as UserTopPostsRank,
    string_agg(distinct nullif(t.TagName, '') , ',' order by t.TagName) over (partition by u.Id) as UserTags,
    case when exists (
      select 1 from Comments c where c.PostId = p.Id and c.Score > 5
    ) then 'Yes' else 'No' end as HasHighlyVotedComments,
    length(coalesce(p.Body,'')::text) as PostBodyLength,
    case 
        when p.ClosedDate is not null then 'Closed'
        when lastph.PostHistoryTypeId = 11 then 'Reopened'
        else 'Open'
    end as PostStatus,
    -- correlated subquery to find number of other posts linked as duplicate
    coalesce((
        select count(*) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3
    ), 0) as DuplicateLinksCount,
    -- string manipulation: extract first tag or fallback
    coalesce(
        substring(p.Tags from '<([^>]+)>'),
        'no-tag'
    ) as FirstTag,
    -- NULL logic in COALESCE to protect against missing CreationDate
    coalesce(p.CreationDate, u.CreationDate) as EffectiveCreationDate
from Users u
left join UserBadgeStats ub on u.Id = ub.UserId
left join Posts p on p.OwnerUserId = u.Id
left join LatestPostHistory ph on ph.PostId = p.Id and ph.rn = 1
left join LatestPostHistory lastph on lastph.PostId = p.Id and lastph.rn = 1
left join PostVoteSummary pvs on p.Id = pvs.PostId
left join Tags t on strpos(coalesce(p.Tags,''), concat('<', t.TagName, '>')) > 0
where u.Reputation > 1000
  and (p.PostTypeId = 1 or p.PostTypeId is null)
  and (ph.PostHistoryTypeId is null or ph.PostHistoryTypeId != 12) -- exclude deleted posts history
order by u.Reputation desc, p.Score desc nulls last
limit 100;