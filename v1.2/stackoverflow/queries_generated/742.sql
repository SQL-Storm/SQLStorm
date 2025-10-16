-- {"query": "742.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1388} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1, 2)) as TotalPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as LastPostRank,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
RecentPostsWithComments as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.UserId as CommentUserId,
        c.CreationDate as CommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id and c.CreationDate > p.CreationDate - interval '30 days'
    where p.CreationDate > current_date - interval '1 year'
),
UserBadgeAggregation as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeNames
    from Badges b
    group by b.UserId
),
TopPostsWithAcceptedAnswer as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        u.DisplayName as AcceptedAnswerOwnerName,
        p.Tags,
        p.CreationDate
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where p.PostTypeId = 1
    and p.Score > 10
),
PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
UserActivityWindow as (
    select
        UserId,
        CreationDate,
        Reputation,
        sum(AnswerCount) over (partition by UserId order by CreationDate rows between 29 preceding and current row) as RollingAnswerCount,
        sum(QuestionCount) over (partition by UserId order by CreationDate rows between 29 preceding and current row) as RollingQuestionCount,
        avg(Reputation) over (partition by UserId order by CreationDate rows between 29 preceding and current row) as AvgReputation30Days
    from RecursiveUserActivity
),
PostsWithComplexTagLogic as (
    select
        p.Id,
        p.Title,
        p.Tags,
        string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><') as TagArray,
        cardinality(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagCount,
        p.Score,
        p.ViewCount
    from Posts p
    where p.PostTypeId = 1
    and p.Tags is not null
    and p.Tags like '%<sql>%'
),
FinalAggregatedResults as (
    select
        u.Id as UserId,
        u.DisplayName,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.DistinctBadgeNames,
        ra.QuestionCount,
        ra.AnswerCount,
        ra.TotalPostScore,
        max(tp.Score) filter (where tp.AcceptedAnswerId is not null) as MaxAcceptedAnswerScore,
        count(distinct pl.PostId) as DuplicatePostCount,
        max(pwcl.TagCount) as MaxTagCountInSqlTaggedPosts,
        max(ua.Reputation) over () as MaxReputation,
        min(ua.Reputation) over () as MinReputation,
        avg(ua.Reputation) over () as AvgReputation
    from Users u
    left join UserBadgeAggregation ua on ua.UserId = u.Id
    left join RecursiveUserActivity ra on ra.UserId = u.Id
    left join TopPostsWithAcceptedAnswer tp on tp.AcceptedAnswerOwner = u.Id
    left join PostLinkDuplicates pl on pl.RelatedPostId = u.Id
    left join PostsWithComplexTagLogic pwcl on pwcl.Id = any (
        select p.Id from Posts p where p.OwnerUserId = u.Id
    )
    group by u.Id, u.DisplayName, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ua.DistinctBadgeNames, ra.QuestionCount, ra.AnswerCount, ra.TotalPostScore
)
select
    UserId,
    DisplayName,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    DistinctBadgeNames,
    QuestionCount,
    AnswerCount,
    TotalPostScore,
    coalesce(MaxAcceptedAnswerScore, 0) as MaxAcceptedAnswerScore,
    DuplicatePostCount,
    MaxTagCountInSqlTaggedPosts,
    MaxReputation,
    MinReputation,
    AvgReputation,
    case
        when TotalPostScore > 1000 then 'High Scorer'
        when TotalPostScore between 500 and 1000 then 'Medium Scorer'
        else 'Low Scorer'
    end as ScorerCategory
from FinalAggregatedResults
where (GoldBadges + SilverBadges + BronzeBadges) > 10
order by TotalPostScore desc
limit 100;