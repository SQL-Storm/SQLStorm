-- {"query": "2645.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1477} 
with RecursiveCTE as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        case when p.Tags is not null then string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><') else array[]::varchar[] end as TagArray,
        1 as Depth
    from Posts p
    where p.PostTypeId = 1 -- questions only

    union all

    select
        p2.Id,
        p2.OwnerUserId,
        p2.PostTypeId,
        p2.Score,
        p2.ViewCount,
        p2.CreationDate,
        case when p2.Tags is not null then string_to_array(substring(p2.Tags from 2 for length(p2.Tags) - 2), '><') else array[]::varchar[] end,
        r.Depth + 1
    from Posts p2
    join RecursiveCTE r on p2.ParentId = r.PostId
    where r.Depth < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostVoteStats as (
    select
        v.PostId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotes,
        count(*) filter (where vt.Name = 'DownMod') as DownVotes,
        count(*) filter (where vt.Name = 'Favorite') as Favorites,
        count(*) as TotalVotes,
        max(v.BountyAmount) as MaxBounty
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as PostRank,
        count(*) over (partition by u.Id) as TotalPosts,
        sum(p.Score) over (partition by u.Id) as TotalPostScore,
        max(p.Score) over (partition by u.Id) as MaxPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
QualifiedPosts as (
    select
        r.PostId,
        r.OwnerUserId,
        r.PostTypeId,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.TagArray,
        pvs.UpVotes,
        pvs.DownVotes,
        pvs.Favorites,
        pvs.TotalVotes,
        pvs.MaxBounty,
        usb.GoldBadges,
        usb.SilverBadges,
        usb.BronzeBadges,
        pac.CloseReasonName,
        uact.PostRank,
        uact.TotalPosts,
        uact.TotalPostScore,
        uact.MaxPostScore
    from RecursiveCTE r
    left join PostVoteStats pvs on r.PostId = pvs.PostId
    left join UserBadgeCounts usb on r.OwnerUserId = usb.UserId
    left join PostCloseReasons pac on r.PostId = pac.PostId
    left join UserActivityWindow uact on r.OwnerUserId = uact.UserId and uact.PostRank = 1
    where r.PostTypeId in (1,2)
)
select distinct
    qp.PostId,
    qp.OwnerUserId,
    coalesce(u.DisplayName, qp.OwnerUserId::varchar) as OwnerDisplayName,
    qp.PostTypeId,
    case qp.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostTypeName,
    qp.Score,
    qp.ViewCount,
    qp.CreationDate,
    array_to_string(qp.TagArray, ', ') as Tags,
    qp.UpVotes,
    qp.DownVotes,
    qp.Favorites,
    qp.TotalVotes,
    qp.MaxBounty,
    coalesce(qp.GoldBadges,0) as GoldBadges,
    coalesce(qp.SilverBadges,0) as SilverBadges,
    coalesce(qp.BronzeBadges,0) as BronzeBadges,
    qp.CloseReasonName,
    qp.PostRank,
    qp.TotalPosts,
    qp.TotalPostScore,
    qp.MaxPostScore,
    -- Complex calculation involving null logic and string manipulation
    case
        when qp.UpVotes is null or qp.DownVotes is null then 'Insufficient vote data'
        when qp.DownVotes = 0 then to_char(qp.UpVotes, 'FM999999')
        else to_char((qp.UpVotes::float / (qp.DownVotes + 1)), 'FM999999.00')
    end as UpDownRatio,
    -- Example of correlated subquery with EXISTS for performance impact
    exists (
        select 1
        from Comments c
        where c.PostId = qp.PostId
          and c.Score > 5
          and (
            lower(c.Text) like '%performance%'
            or lower(c.Text) like '%benchmark%'
          )
    ) as HasHighScorePerformanceComments,
    -- Window function for rank by score within tags
    rank() over (
        partition by unnest(qp.TagArray)
        order by qp.Score desc nulls last
    ) as RankByTagScore,
    -- Null-safe string concatenation showing owner and possible last editor name
    coalesce(u.DisplayName, 'Anonymous') || ' / ' || coalesce(le.DisplayName, 'No Editor') as Owner_Editor
from QualifiedPosts qp
left join Users u on qp.OwnerUserId = u.Id
left join Users le on le.Id = (
    select ph.LastEditorUserId
    from Posts p2
    join PostHistory ph on p2.Id = ph.PostId
    where p2.Id = qp.PostId
    order by ph.CreationDate desc
    limit 1
)
where qp.Score > 10
  and qp.TotalPosts > 5
  and (qp.CloseReasonName is null or qp.CloseReasonName not in ('Duplicate', 'Off-topic'))
order by qp.Score desc nulls last, qp.ViewCount desc nulls last
limit 100;