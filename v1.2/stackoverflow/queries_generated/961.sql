-- {"query": "961.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1313} 
with recursive RecentUsers as (
    select Id, DisplayName, Reputation, CreationDate, Location,
           row_number() over (order by Reputation desc, CreationDate asc) as rn
    from Users
    where Location is not null
    limit 100
),
UserBadgeCounts as (
    select UserId,
           count(*) filter (where Class = 1) as GoldBadges,
           count(*) filter (where Class = 2) as SilverBadges,
           count(*) filter (where Class = 3) as BronzeBadges,
           count(distinct Name) as DistinctBadges
    from Badges
    where UserId in (select Id from RecentUsers)
    group by UserId
),
TopQuestions as (
    select p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
           coalesce(p.FavoriteCount, 0) as FavoriteCount,
           u.DisplayName as OwnerName,
           dense_rank() over (partition by OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    left join RecentUsers u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.OwnerUserId in (select Id from RecentUsers)
),
QuestionsWithAnswers as (
    select q.Id as QuestionId, a.Id as AnswerId, a.Score as AnswerScore, a.OwnerUserId as AnswerOwnerId,
           a.CreationDate as AnswerCreationDate,
           row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.Id in (select Id from TopQuestions where ScoreRank <= 5)
),
AnswerersInfo as (
    select ua.AnswerId, u.DisplayName, u.Reputation, u.Location
    from QuestionsWithAnswers ua
    left join Users u on u.Id = ua.AnswerOwnerId
),
QuestionLinksAgg as (
    select pl.PostId, string_agg(distinct lt.Name || ':' || cast(pl.RelatedPostId as varchar), ', ') as RelatedLinks
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.PostId in (select Id from TopQuestions)
    group by pl.PostId
),
QuestionTagExplode as (
    select q.Id as QuestionId,
           unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) as Tag
    from Posts q
    where q.PostTypeId = 1 and q.Id in (select Id from TopQuestions)
),
TagPopularities as (
    select Tag, count(*) as TagCount,
           avg(p.Score) as AvgQuestionScore,
           max(p.ViewCount) as MaxViewCount
    from QuestionTagExplode qte
    join Posts p on p.Id = qte.QuestionId
    group by Tag
),
FilteredTags as (
    select Tag
    from TagPopularities
    where TagCount > 3 and AvgQuestionScore > 5
),
CloseReasonStats as (
    select cht.Name as CloseReasonName,
           count(distinct ph.PostId) as ClosedPostsCount,
           min(ph.CreationDate) as FirstCloseDate,
           max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserRanking as (
    select Id, DisplayName, Reputation,
           rank() over (order by Reputation desc nulls last, CreationDate asc) as UserRank,
           count(distinct (select b.Id from Badges b where b.UserId = Users.Id)) as BadgeDiversity
    from Users
    where Reputation > 1000
),
EligibleUsers as (
    select * from UserRanking where UserRank <= 50 and BadgeDiversity > 3
)
select
    ru.Id as UserId,
    ru.DisplayName,
    ru.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    tq.Title as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViewCount,
    qla.RelatedLinks,
    array_agg(distinct ft.Tag) filter (where ft.Tag is not null) as PopularTags,
    crs.CloseReasonName,
    crs.ClosedPostsCount,
    crs.FirstCloseDate,
    crs.LastCloseDate,
    count(awa.AnswerId) as AnswerCount,
    avg(awa.AnswerScore) as AvgAnswerScore,
    string_agg(distinct awa.DisplayName || ' (' || coalesce(awa.Location, 'Unknown') || ')', '; ') as TopAnswerers
from RecentUsers ru
left join UserBadgeCounts ubc on ubc.UserId = ru.Id
left join TopQuestions tq on tq.OwnerUserId = ru.Id and tq.ScoreRank = 1
left join QuestionLinksAgg qla on qla.PostId = tq.Id
left join FilteredTags ft on ft.Tag in (
    select unnest(string_to_array(substring(tq.Tags, 2, length(tq.Tags) - 2), '><'))
)
left join CloseReasonStats crs on 1=1 -- cross join to include all close reasons
left join QuestionsWithAnswers qwa on qwa.QuestionId = tq.Id
left join AnswerersInfo awa on awa.AnswerId = qwa.AnswerId
where ru.Id in (select Id from EligibleUsers)
group by ru.Id, ru.DisplayName, ru.Reputation, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
         tq.Title, tq.Score, tq.ViewCount, qla.RelatedLinks, crs.CloseReasonName, crs.ClosedPostsCount, crs.FirstCloseDate, crs.LastCloseDate
order by ru.Reputation desc, tq.Score desc, crs.ClosedPostsCount desc
limit 50;