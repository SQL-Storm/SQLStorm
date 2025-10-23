-- {"query": "783.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1141} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct b.Id) as BadgesCount,
        count(distinct c.Id) as CommentsCount,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
TopUsersCTE as (
    select *
    from RecursiveUserActivity
    where LocationRank <= 10
),
PostAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as PostScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
FilteredPosts as (
    select pa.*
    from PostAggregates pa
    where pa.PostScoreRank <= 50
),
PostLinkDetails as (
    select
        pl.Id,
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId in (1, 3)
),
CombinedPosts as (
    select
        fp.Id,
        fp.PostTypeId,
        fp.OwnerUserId,
        fp.CreationDate,
        fp.Score,
        fp.ViewCount,
        fp.Title,
        fp.Tags,
        fp.AcceptedAnswerId,
        fp.UpVotes,
        fp.DownVotes,
        fp.CommentCount,
        case when fp.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        case when fp.ViewCount > 10000 then 1 else 0 end as IsHighView,
        string_agg(distinct pl.LinkTypeName || ':' || coalesce(pl.RelatedPostTitle, 'N/A'), '; ') filter (where pl.PostId = fp.Id) as LinkSummary
    from FilteredPosts fp
    left join PostLinkDetails pl on pl.PostId = fp.Id
    group by fp.Id, fp.PostTypeId, fp.OwnerUserId, fp.CreationDate, fp.Score, fp.ViewCount, fp.Title, fp.Tags, fp.AcceptedAnswerId, fp.UpVotes, fp.DownVotes, fp.CommentCount
),
UserBadgesRanked as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as BadgeRank
    from Badges b
    where b.Class in (1, 2, 3)
),
UserTopBadges as (
    select
        ubr.UserId,
        string_agg(ubr.BadgeName || '(' || ubr.Class || ')', ', ') as TopBadges
    from UserBadgesRanked ubr
    where ubr.BadgeRank <= 5
    group by ubr.UserId
),
FinalResult as (
    select
        cu.Id as PostId,
        cu.Title,
        cu.PostTypeId,
        cu.Score,
        cu.ViewCount,
        cu.UpVotes,
        cu.DownVotes,
        cu.CommentCount,
        cu.HasAcceptedAnswer,
        cu.IsHighView,
        cu.LinkSummary,
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.Location,
        ru.QuestionsCount,
        ru.AnswersCount,
        coalesce(utb.TopBadges, 'No Badges') as TopBadges,
        ru.LocationRank,
        row_number() over (partition by ru.Location order by cu.Score desc) as PostRankInLocation
    from CombinedPosts cu
    left join RecursiveUserActivity ru on ru.UserId = cu.OwnerUserId
    left join UserTopBadges utb on utb.UserId = cu.OwnerUserId
    where ru.Location is not null
)
select *
from FinalResult
where PostRankInLocation <= 5
order by Location, PostRankInLocation, Score desc;