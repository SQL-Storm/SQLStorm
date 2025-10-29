-- {"query": "2586.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1422} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        u.Id as OwnerUserId,
        u.Reputation,
        Row_Number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Tags is not null
        and (',' || substring(p.Tags from 2 for length(p.Tags)-2) || ',') like concat('%,', t.TagName, ',%')
        and p.PostTypeId = 1
    left join Users u on p.OwnerUserId = u.Id
    where t.IsModeratorOnly = 0
),
TopPostsPerTag as (
    select *
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(sum(p.ViewCount), 0) as TotalPostViews,
        coalesce(max(p.CreationDate), '1900-01-01') as LastPostDate,
        max(case when b.Class = 1 then bc.BadgeCount else 0 end) as GoldBadges,
        max(case when b.Class = 2 then bc.BadgeCount else 0 end) as SilverBadges,
        max(case when b.Class = 3 then bc.BadgeCount else 0 end) as BronzeBadges,
        rank() over (order by u.Reputation desc, coalesce(sum(p.Score), 0) desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join UserBadgeCounts bc on bc.UserId = u.Id and bc.Class = b.Class
    group by u.Id, u.DisplayName, u.Reputation
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
PostVoteAggregates as (
    select
        v.PostId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotes,
        count(*) filter (where vt.Name = 'DownMod') as DownVotes,
        count(*) filter (where vt.Name = 'Favorite') as FavoriteVotes,
        count(*) filter (where vt.Name = 'Close') as CloseVotes,
        count(*) filter (where vt.Name = 'Reopen') as ReopenVotes
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct c.UserDisplayName || ':' || substring(c.Text from 1 for 20), ' ||| ') as RecentCommentSnippets
    from Comments c
    group by c.PostId
),
ComplexPostInfo as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.PostTypeId,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        vagg.UpVotes,
        vagg.DownVotes,
        vagg.FavoriteVotes,
        vagg.CloseVotes,
        vagg.ReopenVotes,
        pla.LinkedCount,
        pla.DuplicateCount,
        coalesce(cm.CommentCount,0) as CommentCount,
        cm.LastCommentDate,
        cm.RecentCommentSnippets,
        case
          when p.ClosedDate is not null then true
          else false
        end as IsClosed,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join PostVoteAggregates vagg on vagg.PostId = p.Id
    left join PostLinkAggregates pla on pla.PostId = p.Id
    left join PostComments cm on cm.PostId = p.Id
    where p.PostTypeId in (1,2)
)
select distinct
    cpi.Id as PostId,
    cpi.Title,
    cpi.CreationDate,
    cpi.Score,
    cpi.ViewCount,
    cpi.Tags,
    cpi.PostTypeId,
    cpi.OwnerName,
    cpi.OwnerReputation,
    cpi.UpVotes,
    cpi.DownVotes,
    cpi.FavoriteVotes,
    cpi.CloseVotes,
    cpi.ReopenVotes,
    cpi.LinkedCount,
    cpi.DuplicateCount,
    cpi.CommentCount,
    cpi.LastCommentDate,
    left(cpi.RecentCommentSnippets, 150) as RecentCommentSnippetsPartial,
    cpi.IsClosed,
    cpi.RankByScore,
    ut.TagName,
    ut.Count as TagGlobalCount,
    ut.Score as PostTagScore,
    ut.ViewCount as PostTagViewCount,
    ua.UserRank,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    -- Correlated subquery: Latest edit comment by the post owner
    (
        select ph.Comment
        from PostHistory ph
        where ph.PostId = cpi.Id
          and ph.UserId = (select Id from Users where DisplayName = cpi.OwnerName limit 1)
          and ph.Comment is not null
        order by ph.CreationDate desc
        limit 1
    ) as LatestOwnerEditComment
from ComplexPostInfo cpi
left join TopPostsPerTag ut on ut.PostId = cpi.Id
left join UserAggregates ua on ua.DisplayName = cpi.OwnerName
where (cpi.Score > 10 or cpi.ViewCount > 1000)
  and (cpi.IsClosed = false or cpi.CloseVotes < 2)
order by ua.UserRank, cpi.Score desc, cpi.ViewCount desc
limit 100;