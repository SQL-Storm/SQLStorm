-- {"query": "674.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2092} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        u.Id as OwnerUserId,
        u.Reputation,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc nulls last, p.ViewCount desc nulls last) as PostRank
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
TopPostsByTag as (
    select
        TagId,
        TagName,
        PostId,
        Score,
        ViewCount,
        OwnerUserId,
        Reputation,
        DisplayName,
        PostRank
    from RecursiveTagCounts
    where PostRank <= 5
),
UserBadgesAgg as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeCount,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(uba.GoldBadges, 0) as GoldBadges,
        coalesce(uba.SilverBadges, 0) as SilverBadges,
        coalesce(uba.BronzeBadges, 0) as BronzeBadges,
        coalesce(uba.DistinctBadgeCount, 0) as DistinctBadgeCount,
        uba.LastBadgeDate,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id) as AvgPostScore,
        (select max(p.Score) from Posts p where p.OwnerUserId = u.Id) as MaxPostScore,
        case when u.Location ilike '%United States%' then 'USA'
             when u.Location ilike '%India%' then 'India'
             when u.Location ilike '%United Kingdom%' then 'UK'
             else 'Other' end as Region
    from Users u
    left join UserBadgesAgg uba on uba.UserId = u.Id
),
PostVotesAgg as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoriteVotes,
        count(v.Id) filter (where v.VoteTypeId = 8 or v.VoteTypeId = 9) as BountyVotes,
        sum(coalesce(v.BountyAmount,0)) as TotalBountyAmount
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
PostWithVotesAndLinks as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.LastActivityDate,
        p.ContentLicense,
        pvo.UpVotes,
        pvo.DownVotes,
        pvo.FavoriteVotes,
        pvo.BountyVotes,
        pvo.TotalBountyAmount,
        count(pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateLinksCount,
        count(pl.Id) filter (where pl.LinkTypeId = 1) as LinkedPostsCount
    from Posts p
    left join PostVotesAgg pvo on pvo.PostId = p.Id
    left join PostLinks pl on pl.PostId = p.Id
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.AcceptedAnswerId, p.ParentId, p.ClosedDate, p.LastActivityDate, p.ContentLicense, pvo.UpVotes, pvo.DownVotes, pvo.FavoriteVotes, pvo.BountyVotes, pvo.TotalBountyAmount
),
DetailedPostAnalysis as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        p.AcceptedAnswerId,
        case when p.ClosedDate is not null then true else false end as IsClosed,
        p.LastActivityDate,
        p.ContentLicense,
        p.UpVotes,
        p.DownVotes,
        p.FavoriteVotes,
        p.BountyVotes,
        p.TotalBountyAmount,
        p.DuplicateLinksCount,
        p.LinkedPostsCount,
        -- Correlated subquery for count of comments with positive score on post
        (select count(*) from Comments c where c.PostId = p.Id and c.Score > 0) as PositiveCommentsCount,
        -- Window function: rank posts by score over owner
        rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as OwnerPostScoreRank,
        -- String expression: truncated and concatenated tags
        case when p.Tags is not null then substring(p.Tags from 1 for 100) || '...' else 'No Tags' end as ShortTags,
        -- NULL logic with COALESCE
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerIdSafe
    from PostWithVotesAndLinks p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
ClosedReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(p.LastActivityDate) as LastPostActivity,
        max(ph.CreationDate) as LastHistoryActivity,
        greatest(
            coalesce(max(p.LastActivityDate), '1970-01-01'::timestamp),
            coalesce(max(ph.CreationDate), '1970-01-01'::timestamp)
        ) as LastOverallActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
),
FinalResult as (
    select
        dpa.Id as QuestionId,
        dpa.Title,
        dpa.CreationDate,
        dpa.Score,
        dpa.ViewCount,
        dpa.ShortTags,
        dpa.OwnerUserId,
        dpa.OwnerDisplayName,
        dpa.OwnerReputation,
        dpa.AcceptedAnswerIdSafe,
        dpa.IsClosed,
        crc.CloseReasonName,
        crc.CloseVotesCount,
        dpa.PositiveCommentsCount,
        dpa.UpVotes,
        dpa.DownVotes,
        dpa.FavoriteVotes,
        dpa.BountyVotes,
        dpa.TotalBountyAmount,
        dpa.DuplicateLinksCount,
        dpa.LinkedPostsCount,
        dpa.OwnerPostScoreRank,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.DistinctBadgeCount,
        ua.LastBadgeDate,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        ua.MaxPostScore,
        ua.Region,
        ur.LastOverallActivity,
        -- Complex predicate: flag hot question if score > 100 and viewcount > 10000 and not closed
        case when dpa.Score > 100 and dpa.ViewCount > 10000 and dpa.IsClosed = false then true else false end as IsHotQuestion,
        -- Set operator: check if user is in top 10% by reputation using a window function
        case when ur2.ReputationRank <= (0.1 * ur2.TotalUsers) then true else false end as IsTop10PercentUser
    from DetailedPostAnalysis dpa
    left join ClosedReasonCounts crc on crc.PostId = dpa.Id
    left join UserActivity ua on ua.Id = dpa.OwnerUserId
    left join UserRecentActivity ur on ur.UserId = dpa.OwnerUserId
    left join (
        select
            u.Id,
            u.Reputation,
            rank() over (order by u.Reputation desc) as ReputationRank,
            count(*) over () as TotalUsers
        from Users u
    ) ur2 on ur2.Id = dpa.OwnerUserId
    where dpa.CreationDate >= cast('2024-10-01' as date) - interval '365 days'
)
select *
from FinalResult
order by Score desc nulls last, ViewCount desc nulls last, CreationDate desc
limit 100;