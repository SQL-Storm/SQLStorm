-- {"query": "48.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1424} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) as HighestBadgeClass,
        row_number() over (partition by u.Id order by ph.CreationDate desc nulls last) as LastEditRank,
        ph.CreationDate as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes, ph.CreationDate
),
TopUsers as (
    select *
    from RecursiveUserActivity
    where LastEditRank = 1
    and Reputation > 10000
    and QuestionCount > 10
    and AnswerCount > 20
),
PostWithStats as (
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
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        case when p.PostTypeId = 1 then
            (select count(*) from Posts a where a.ParentId = p.Id and a.Score > 0)
        else null end as PositiveAnswerCount,
        case when p.PostTypeId = 1 then
            (select avg(score) from Posts a where a.ParentId = p.Id)
        else null end as AvgAnswerScore,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate > current_date - interval '1 year'
),
FilteredPosts as (
    select *
    from PostWithStats
    where UserPostRank <= 5
    and (Tags is not null and Tags like '%<sql>%')
    and (Score > 5 or FavoriteCount > 2)
),
PostCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
PostLinksFiltered as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name in ('Linked', 'Duplicate')
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotes
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
)
select
    f.Id as PostId,
    f.Title,
    f.OwnerUserId,
    f.OwnerDisplayName,
    f.OwnerReputation,
    f.PostTypeId,
    f.Score,
    f.ViewCount,
    f.AnswerCount,
    f.PositiveAnswerCount,
    round(f.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    f.CommentCount,
    coalesce(pca.CommentCount,0) as TotalComments,
    coalesce(pca.PositiveComments,0) as PositiveComments,
    pca.Commenters,
    plf.LinkTypeName,
    plf.RelatedPostId,
    phcr.CloseReasonName,
    phcr.CloseVotes,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.HasTagBasedBadge,
    case
        when f.ClosedDate is not null then 'Closed'
        when f.AcceptedAnswerId is not null then 'Answered'
        else 'Open'
    end as PostStatus,
    dense_rank() over (partition by f.OwnerUserId order by f.Score desc) as ScoreRankPerUser,
    case
        when f.Score > 50 then 'HighScore'
        when f.Score between 20 and 50 then 'MediumScore'
        else 'LowScore'
    end as ScoreCategory,
    concat_ws(' | ',
        coalesce(f.Tags, 'NoTags'),
        coalesce(f.Title, 'NoTitle'),
        coalesce(f.OwnerDisplayName, 'UnknownUser')
    ) as CompositeString,
    length(coalesce(f.Body, '')) as BodyLength,
    (select count(*) from Votes v where v.PostId = f.Id and v.VoteTypeId = 2) as UpVotesCount,
    (select count(*) from Votes v where v.PostId = f.Id and v.VoteTypeId = 3) as DownVotesCount,
    (select count(*) from Votes v where v.PostId = f.Id and v.VoteTypeId = 5) as FavoriteVotesCount
from FilteredPosts f
left join PostCommentsAgg pca on pca.PostId = f.Id
left join PostLinksFiltered plf on plf.PostId = f.Id
left join PostHistoryCloseReasons phcr on phcr.PostId = f.Id
left join UserBadgeSummary ubs on ubs.UserId = f.OwnerUserId
where f.OwnerUserId in (select UserId from TopUsers)
order by f.OwnerReputation desc, f.Score desc, f.CreationDate desc
limit 100;