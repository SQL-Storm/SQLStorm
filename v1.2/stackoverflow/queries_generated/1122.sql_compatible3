with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from 
        Users u
    left join 
        Badges b on u.Id = b.UserId
    where 
        b.Date is not null
),
TopBadgesPerUser as (
    select 
        UserId,
        DisplayName,
        BadgeName,
        Class,
        Date
    from
        RecursiveUserBadges
    where BadgeRank <= 3
),
PostWithAnswerStats as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        coalesce(ans.Score,0) as AcceptedAnswerScore,
        coalesce(ans.OwnerUserId, -1) as AcceptedAnswerOwner,
        case when p.AcceptedAnswerId is not null then 'Yes' else 'No' end as HasAcceptedAnswer,
        row_number() over (partition by p.Id order by p.CreationDate desc) as PostRank
    from Posts p
    left join Posts ans on p.AcceptedAnswerId = ans.Id and ans.PostTypeId = 2
    where p.PostTypeId = 1
),
PostCommentsAggregate as (
    select 
        c.PostId,
        count(distinct c.Id) as CommentCount,
        sum(coalesce(c.Score,0)) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate
    from 
        Comments c
    group by 
        c.PostId
),
UserReputationStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from 
        Users u
    left join (
        select 
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from 
            Badges
        group by 
            UserId
    ) bc on u.Id = bc.UserId
),
PostLinksWithTypes as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        pl.CreationDate
    from 
        PostLinks pl
    join 
        LinkTypes lt on pl.LinkTypeId = lt.Id
),
QuestionsWithDuplicates as (
    select 
        p.Id as QuestionId, 
        p.Title,
        count(distinct case when pl.LinkTypeName = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        max(pl.CreationDate) as LastLinkDate
    from 
        Posts p
    left join 
        PostLinksWithTypes pl on pl.PostId = p.Id
    where 
        p.PostTypeId = 1
    group by 
        p.Id, p.Title
),
WindowedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc NULLS LAST) as ScoreRank,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType
    from Posts p
),
CorrelatedUserLastCommentDate as (
    select 
        u.Id as UserId,
        (
            select max(c.CreationDate) 
            from Comments c 
            join Posts p on c.PostId = p.Id 
            where p.OwnerUserId = u.Id
        ) as LastUserCommentDate
    from Users u
),
HighActivityUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        case 
            when count(distinct p.Id) > 50 and count(distinct c.Id) > 100 then 'High Activity'
            when count(distinct p.Id) > 50 then 'More Posts'
            when count(distinct c.Id) > 100 then 'More Comments'
            else 'Low Activity'
        end as ActivityLevel
    from 
        Users u
    left join 
        Posts p on p.OwnerUserId = u.Id
    left join 
        Comments c on c.UserId = u.Id
    group by 
        u.Id, u.DisplayName, u.Reputation
)
select 
    wu.Id as PostId,
    wu.PostTypeId,
    wu.Title,
    concat(
        'Score Rank: ', cast(wu.ScoreRank as varchar), '/', cast(wu.TotalPostsOfType as varchar),
        ' | ',
        coalesce(cast(qus.DuplicateCount as varchar), '0'), ' Duplicates',
        ' | ',
        case when pwa.HasAcceptedAnswer = 'Yes' then 'Has Accepted Answer' else 'No Accepted Answer' end
    ) as Summary,
    pwa.Score as QuestionScore,
    pwa.ViewCount,
    pwa.CreationDate,
    pca.CommentCount, 
    pca.TotalCommentScore,
    pca.LastCommentDate,
    urep.DisplayName as OwnerDisplayName,
    urep.Reputation as OwnerReputation,
    urep.GoldBadges,
    urep.SilverBadges,
    urep.BronzeBadges,
    cb.LastUserCommentDate,
    hb.ActivityLevel,
    tbp.BadgeName as TopUserBadge,
    tbp.Class as BadgeClass,
    case 
        when pwa.AcceptedAnswerScore > pwa.Score then 'Accepted Answer Score Higher'
        when pwa.AcceptedAnswerScore = pwa.Score then 'Accepted Answer Score Equal'
        else 'Accepted Answer Score Lower'
    end as ScoreComparison,
    case 
        when wu.Tags IS NULL then '[]'
        else string_agg(tags.tag, ',' ORDER BY tags.tag)
    end as ParsedTags
from 
    WindowedPosts wu
join 
    PostWithAnswerStats pwa on pwa.Id = wu.Id
left join 
    PostCommentsAggregate pca on pca.PostId = wu.Id
left join 
    UserReputationStats urep on urep.Id = pwa.OwnerUserId
left join
    CorrelatedUserLastCommentDate cb on cb.UserId = urep.Id
left join
    HighActivityUsers hb on hb.Id = urep.Id
left join
    TopBadgesPerUser tbp on tbp.UserId = urep.Id and tbp.Date = (
        select max(Date) from TopBadgesPerUser tb where tb.UserId = urep.Id
    )
left join 
    QuestionsWithDuplicates qus on qus.QuestionId = wu.Id and wu.PostTypeId = 1
left join lateral (
    select unnest(string_to_array(
        regexp_replace(coalesce(wu.Tags,'<>'), '^<|>$',''), '><'
    )) as tag
) tags on true
where 
    wu.PostTypeId in (1,2)
    and (wu.Score is not null and wu.Score >= 10)
group by
    wu.Id,
    wu.PostTypeId,
    wu.Title,
    wu.ScoreRank,
    wu.TotalPostsOfType,
    qus.DuplicateCount,
    pwa.HasAcceptedAnswer,
    pwa.Score,
    pwa.ViewCount,
    pwa.CreationDate,
    pca.CommentCount,
    pca.TotalCommentScore,
    pca.LastCommentDate,
    urep.DisplayName,
    urep.Reputation,
    urep.GoldBadges,
    urep.SilverBadges,
    urep.BronzeBadges,
    cb.LastUserCommentDate,
    hb.ActivityLevel,
    tbp.BadgeName,
    tbp.Class,
    pwa.AcceptedAnswerScore,
    wu.Tags
order by 
    wu.ScoreRank
limit 50;