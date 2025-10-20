with RecursiveUserBadgeRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Class, b.Date) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
), LatestUserPosts as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.OwnerUserId is not null
), FilteredRecentPosts as (
    select * from LatestUserPosts where rn <= 5
), TagExploded as (
    select
        p.Id as PostId,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
), UserTagAggregates as (
    select
        p.OwnerUserId,
        te.Tag,
        count(*) as QuestionsWithTag,
        avg(p.Score) as AvgScorePerTag
    from Posts p
    join TagExploded te on te.PostId = p.Id
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId, te.Tag
), UserRankedTagAggregates as (
    select
        uta.OwnerUserId,
        uta.Tag,
        uta.QuestionsWithTag,
        uta.AvgScorePerTag,
        row_number() over (partition by uta.OwnerUserId order by uta.QuestionsWithTag desc, uta.AvgScorePerTag desc) as TagRank
    from UserTagAggregates uta
), QuestionAnswerScoreWindow as (
    select
        q.Id as QuestionId,
        q.Title,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        avg(a.Score) over (partition by q.Id) as AvgAnswerScore,
        rank() over (partition by q.Id order by a.Score desc NULLS LAST) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
), QuestionDuplicateLinkCount as (
    select
        pl.PostId,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
), ComplexPostInfo as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        coalesce(dupl.DuplicateCount,0) as DuplicateLinks,
        (q.Score * 2 + q.ViewCount / 100.0) - (coalesce(dupl.DuplicateCount,0) * 10) as ComplexScore,
        (case when q.ClosedDate is not null then 1 else 0 end) as IsClosed,
        row_number() over (order by 
            (q.Score * 2 + q.ViewCount / 100.0) - (coalesce(dupl.DuplicateCount,0) * 10) desc,
            q.ViewCount desc) as ComplexRank
    from Posts q
    left join QuestionDuplicateLinkCount dupl on dupl.PostId = q.Id
    where q.PostTypeId = 1
), UserBadgeClassMax as (
    select
        ru.UserId,
        max(ru.Class) as RankBasedOnBadgeClass
    from RecursiveUserBadgeRanks ru
    group by ru.UserId
)
select
    'BadgeClassRank' as RankType,
    du.Id as UserId,
    u.DisplayName,
    du.ComplexRank,
    du.Title as QuestionTitle,
    substring(du.Title from 1 for 50) || coalesce('...' , '') as ShortTitle,
    du.ComplexScore,
    du.DuplicateLinks,
    du.IsClosed,
    case when ru.BadgeRank is null then 0 else 1 end as HasBadges,
    coalesce(ub.RankBasedOnBadgeClass, 0) as BadgeClassRank,
    ut.Tag as TopTagByUser,
    ut.QuestionsWithTag,
    ut.AvgScorePerTag,
    (select count(*) 
     from Comments c 
     where c.PostId = du.Id and c.CreationDate >= cast('2024-10-01' as date) - interval '30 days') as RecentCommentsOnPosts,
    (select count(*) from Votes v where v.PostId = du.Id and v.VoteTypeId = 2) as UpVotesOnQuestion,
    (select max(p.CreationDate) from Posts p where p.OwnerUserId = du.Id) as LastPostDate
from
    ComplexPostInfo du
join Users u on u.Id = du.Id
left join RecursiveUserBadgeRanks ru on ru.UserId = u.Id and ru.BadgeRank = 1
left join UserRankedTagAggregates ut on ut.OwnerUserId = u.Id and ut.TagRank = 1
left join UserBadgeClassMax ub on ub.UserId = u.Id
where du.ComplexRank <= 100
order by du.ComplexRank asc;