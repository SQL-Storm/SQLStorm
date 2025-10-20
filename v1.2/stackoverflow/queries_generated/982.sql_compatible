with RecursiveTags as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as Tag,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivityRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc, u.CreationDate) as ReputationRank,
        rank() over (partition by u.Location order by u.LastAccessDate desc nulls last) as LocationAccessRank,
        coalesce(bc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(bc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(bc_bronze.BadgeCount, 0) as BronzeBadges
    from Users u
    left join UserBadgeCounts bc_gold on bc_gold.UserId = u.Id and bc_gold.Class = 1
    left join UserBadgeCounts bc_silver on bc_silver.UserId = u.Id and bc_silver.Class = 2
    left join UserBadgeCounts bc_bronze on bc_bronze.UserId = u.Id and bc_bronze.Class = 3
),
PostLinksWithDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
),
QuestionsWithAcceptedAnswerScores as (
    select
        p.Id, p.Title, p.Score as QuestionScore, p.ViewCount as QuestionViews,
        aa.Score as AcceptedAnswerScore,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.ClosedDate
    from Posts p
    left join Posts aa on aa.Id = p.AcceptedAnswerId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
CloseReasonCounts as (
    select
        cht.Id,
        cht.Name,
        (select count(*) from PostHistory ph where ph.PostHistoryTypeId = 10 and ph.Comment = cast(cht.Id as varchar)) as CloseCount
    from CloseReasonTypes cht
),
PostEditAggregates as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
UserTopQuestions as (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId,
        p.Id as QuestionId,
        p.Score,
        p.ViewCount,
        p.Title,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
),
TagAggregates as (
    select
        rt.Tag,
        count(distinct rt.PostId) as QuestionCount,
        avg(rt.Score) as AvgScore,
        avg(rt.ViewCount) as AvgViews,
        max(rt.Score) as MaxScore,
        min(rt.Score) as MinScore
    from RecursiveTags rt
    group by rt.Tag
),
UserCommentActivity as (
    select
        c.UserId,
        count(*) as TotalComments,
        avg(c.Score) as AvgCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
)
select
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    uar.ReputationRank,
    uar.LocationAccessRank,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    ta.QuestionCount,
    ta.AvgScore as AvgTagQuestionScore,
    ta.MaxScore as MaxTagQuestionScore,
    ta.MinScore as MinTagQuestionScore,
    uca.TotalComments,
    uca.AvgCommentScore,
    pwa.QuestionId as TopQuestionId,
    pwa.Score as TopQuestionScore,
    pwa.ViewCount as TopQuestionViews,
    pwa.Title as TopQuestionTitle,
    pq.ClosedDate,
    crc.Name as CloseReasonName,
    crc.CloseCount,
    PEA.EditCount,
    PEA.LastEditDate
from UserActivityRanks uar
left join UserCommentActivity uca on uca.UserId = uar.UserId
left join UserTopQuestions pwa on pwa.OwnerUserId = uar.UserId and pwa.ScoreRank = 1
left join QuestionsWithAcceptedAnswerScores pq on pq.Id = pwa.QuestionId
left join (
    select rt.PostId, rt.Tag
    from RecursiveTags rt
    group by rt.PostId, rt.Tag
) rt on rt.PostId = pwa.QuestionId
left join TagAggregates ta on ta.Tag = rt.Tag
left join CloseReasonCounts crc on pq.ClosedDate is not null and crc.CloseCount > 0
left join PostEditAggregates PEA on PEA.PostId = pwa.QuestionId
where uar.Reputation > 1000
group by
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    uar.ReputationRank,
    uar.LocationAccessRank,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    ta.QuestionCount,
    ta.AvgScore,
    ta.MaxScore,
    ta.MinScore,
    uca.TotalComments,
    uca.AvgCommentScore,
    pwa.QuestionId,
    pwa.Score,
    pwa.ViewCount,
    pwa.Title,
    pq.ClosedDate,
    crc.Name,
    crc.CloseCount,
    PEA.EditCount,
    PEA.LastEditDate
order by uar.ReputationRank, uar.LocationAccessRank
limit 100;