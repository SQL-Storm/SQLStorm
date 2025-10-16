-- {"query": "1015.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1509} 
with RecursiveUserBadges as (
  select
    u.Id as UserId,
    u.DisplayName,
    b.Name as BadgeName,
    b.Class,
    row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
  from Users u
  left join Badges b on u.Id = b.UserId
  where b.Date > u.CreationDate + interval '1 year'
),
RecentUserActivity as (
  select
    u.Id as UserId,
    max(p.CreationDate) as LastPostDate,
    max(c.CreationDate) as LastCommentDate,
    max(v.CreationDate) as LastVoteDate
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Votes v on v.UserId = u.Id
  group by u.Id
),
QuestionAnswerStats as (
  select
    q.Id as QuestionId,
    q.OwnerUserId,
    q.Score as QuestionScore,
    coalesce(a.AnswerCount, 0) as AnswerCount,
    coalesce(a.AcceptedAnswerScore, 0) as AcceptedAnswerScore,
    q.ViewCount,
    array_agg(distinct t.TagName) filter (where t.TagName is not null) as Tags
  from Posts q
  left join (
    select
      ParentId,
      count(*) as AnswerCount,
      max(Score) as MaxAnswerScore,
      sum(case when Id = (select AcceptedAnswerId from Posts pq where pq.Id = ParentId) then Score else 0 end) as AcceptedAnswerScore
    from Posts
    where PostTypeId = 2
    group by ParentId
  ) a on a.ParentId = q.Id
  left join LATERAL (
    select unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) as TagName
  ) t on true
  where q.PostTypeId = 1
  group by q.Id, q.OwnerUserId, q.Score, a.AnswerCount, a.AcceptedAnswerScore, q.ViewCount
),
UserRanks as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    rank() over (order by u.Reputation desc nulls last) as ReputationRank,
    dense_rank() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc nulls last) as YearlyRank
  from Users u
),
CloseReasonCounts as (
  select
    ph.PostId,
    crt.Name as CloseReasonName,
    count(*) as CloseCount
  from PostHistory ph
  join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
  where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
  group by ph.PostId, crt.Name
),
ComplexAggregates as (
  select
    u.Id as UserId,
    count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionsCount,
    count(distinct p.Id) filter (where p.PostTypeId=2) as AnswersCount,
    avg(p.Score) filter (where p.PostTypeId=1) as AvgQuestionScore,
    avg(p.Score) filter (where p.PostTypeId=2) as AvgAnswerScore,
    sum(v.BountyAmount) filter (where v.VoteTypeId in (8, 9)) as TotalBountyGiven,
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Votes v on v.UserId = u.Id
  left join PostHistory ph on ph.UserId = u.Id
  group by u.Id
),
LinkedQuestions as (
  select
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lti.Name as LinkTypeName
  from PostLinks pl
  join LinkTypes lti on pl.LinkTypeId = lti.Id
  where pl.LinkTypeId in (1, 3)
),
QuestionsWithDuplicates as (
  select distinct q.Id as QuestionId, q.Title, count(pl.Id) over (partition by pl.PostId) as DuplicateCount
  from Posts q
  left join LinkedQuestions pl on pl.PostId = q.Id and pl.LinkTypeId = 3
  where q.PostTypeId = 1
),
FinalResults as (
  select
    u.DisplayName,
    u.Reputation,
    ur.ReputationRank,
    ur.YearlyRank,
    qb.BadgeName,
    qb.Class as BadgeClass,
    qua.QuestionsCount,
    qua.AnswersCount,
    qua.AvgQuestionScore,
    qua.AvgAnswerScore,
    qua.TotalBountyGiven,
    qua.CloseReopenEvents,
    qas.QuestionId,
    qas.QuestionScore,
    qas.AnswerCount,
    qas.AcceptedAnswerScore,
    qas.ViewCount,
    array_to_string(qas.Tags, ', ') as Tags,
    crc.CloseReasonName,
    crc.CloseCount,
    lw.DuplicateCount
  from Users u
  join UserRanks ur on ur.Id = u.Id
  left join RecursiveUserBadges qb on qb.UserId = u.Id and qb.BadgeRank = 1
  left join ComplexAggregates qua on qua.UserId = u.Id
  left join QuestionAnswerStats qas on qas.OwnerUserId = u.Id
  left join CloseReasonCounts crc on crc.PostId = qas.QuestionId
  left join QuestionsWithDuplicates lw on lw.QuestionId = qas.QuestionId
  where u.Reputation > 1000
)
select
  DisplayName,
  Reputation,
  ReputationRank,
  YearlyRank,
  coalesce(BadgeName, 'No Badge') as TopBadge,
  case BadgeClass when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'None' end as BadgeClass,
  QuestionsCount,
  AnswersCount,
  round(coalesce(AvgQuestionScore,0)::numeric, 2) as AvgQuestionScore,
  round(coalesce(AvgAnswerScore,0)::numeric, 2) as AvgAnswerScore,
  coalesce(TotalBountyGiven,0) as TotalBountyGiven,
  CloseReopenEvents,
  QuestionId,
  QuestionScore,
  AnswerCount,
  AcceptedAnswerScore,
  ViewCount,
  Tags,
  CloseReasonName,
  CloseCount,
  coalesce(DuplicateCount, 0) as DuplicateCount,
  dense_rank() over (order by Reputation desc) as GlobalRank,
  count(*) over () as TotalReturnedUsers
from FinalResults
where (QuestionsCount > 5 or AnswersCount > 10)
  and (CloseCount is null or CloseCount < 5)
order by Reputation desc, QuestionsCount desc, AnswersCount desc
limit 100;