-- {"query": "2608.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1469} 
with RecursiveTagHierarchy as (
  select t.Id, t.TagName, t.WikiPostId, 1 as Level
  from Tags t
  where t.IsModeratorOnly = 0 and t.IsRequired = 0
  union all
  select t2.Id, t2.TagName, t2.WikiPostId, r.Level + 1
  from Tags t2
  join RecursiveTagHierarchy r on r.Id = t2.Id - 1 and r.Level < 3
),
LatestUserActivity as (
  select u.Id as UserId,
    max(coalesce(p.LastActivityDate, c.CreationDate, ph.CreationDate)) as LastActiveDate
  from Users u
  left join Posts p on u.Id = p.OwnerUserId
  left join Comments c on u.Id = c.UserId
  left join PostHistory ph on u.Id = ph.UserId
  group by u.Id
),
UserBadgesSummary as (
  select b.UserId,
    count(case when b.Class = 1 then 1 end) as GoldBadges,
    count(case when b.Class = 2 then 1 end) as SilverBadges,
    count(case when b.Class = 3 then 1 end) as BronzeBadges,
    count(distinct b.Name) as DistinctBadges
  from Badges b
  group by b.UserId
),
QuestionsWithAnswers as (
  select q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionDate,
    q.OwnerUserId,
    q.Score as QuestionScore,
    q.Tags,
    count(a.Id) as AnswerCount,
    avg(a.Score) as AvgAnswerScore,
    max(a.Score) as MaxAnswerScore,
    sum(case when a.Score > q.Score then 1 else 0 end) as AnswersBetterThanQuestion
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.Score, q.Tags
),
PostLinkDetails as (
  select pl.PostId,
    max(case when lt.Name = 'Duplicate' then 1 else 0 end) as IsDuplicateLink,
    count(distinct pl.RelatedPostId) as RelatedPostCount
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
RankedPosts as (
  select p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.Tags,
    row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as RankByScoreView
  from Posts p
  where p.PostTypeId in (1, 2)
),
CorrelatedAnswerStats as (
  select q.Id as QuestionId,
    (select avg(a.Score) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AvgAnswerScore,
    (select count(*) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2 and a.Score > q.Score) as BetterAnswerCount
  from Posts q
  where q.PostTypeId = 1
    and q.Score > 0
),
UserActivityBadgesRanks as (
  select u.Id as UserId, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(ubs.DistinctBadges,0) as DistinctBadges,
    row_number() over (order by u.Reputation desc, coalesce(ubs.GoldBadges,0) desc, u.CreationDate) as RankByRep,
    rank() over (order by u.LastAccessDate desc) as RankByRecentAccess,
    dense_rank() over (partition by u.Location order by u.Reputation desc) as RankByLocationRep
  from Users u
  left join UserBadgesSummary ubs on u.Id = ubs.UserId
)
select
  q.QuestionId,
  left(q.Title, 100) || case when length(q.Title) > 100 then '...' else '' end as ShortTitle,
  q.QuestionDate,
  q.OwnerUserId,
  concat('[', coalesce(q.Tags, ''), ']') as TagsArrayRep,
  q.Score as QuestionScore,
  coalesce(q.AnswerCount, 0) as AnswerCount,
  round(coalesce(q.AvgAnswerScore, 0)::numeric, 2) as AvgAnswerScore,
  q.MaxAnswerScore,
  coalesce(q.AnswersBetterThanQuestion, 0) as AnswersBetterThanQuestion,
  coalesce(pld.IsDuplicateLink, 0) as HasDuplicateLink,
  coalesce(pld.RelatedPostCount, 0) as RelatedLinks,
  ru.RankByScoreView,
  ca.AvgAnswerScore as CorrelatedAvgAnswerScore,
  ca.BetterAnswerCount as CorrelatedBetterAnswerCount,
  ua.DisplayName as QuestionOwner,
  ua.Reputation as OwnerReputation,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.DistinctBadges,
  ua.RankByRep as OwnerRankByRep,
  ua.RankByRecentAccess as OwnerRankByRecentAccess,
  ua.RankByLocationRep as OwnerRankByLocationRep,
  lag(q.Score) over (order by q.Score desc) as PrevQuestionScore,
  lead(q.Score) over (order by q.Score desc) as NextQuestionScore,
  case
    when q.AnswerCount = 0 then 'Unanswered'
    when coalesce(q.MaxAnswerScore, 0) > q.Score then 'Better Answer Exists'
    else 'No Better Answer'
  end as AnswerQualityStatus,
  case when ua.Location is null then 'Unknown' else ua.Location end as OwnerLocationNormalized
from QuestionsWithAnswers q
left join PostLinkDetails pld on q.QuestionId = pld.PostId
left join RankedPosts ru on ru.Id = q.QuestionId
left join CorrelatedAnswerStats ca on ca.QuestionId = q.QuestionId
left join Users ua on ua.Id = q.OwnerUserId
left join UserActivityBadgesRanks ua on ua.UserId = q.OwnerUserId
where q.QuestionDate > now() - interval '5 years'
  and (q.Score > 5 or q.AnswerCount > 2)
  and (ua.Reputation is not null and ua.Reputation > 100)
order by q.Score desc, q.AnswerCount desc, ua.Reputation desc
limit 100;