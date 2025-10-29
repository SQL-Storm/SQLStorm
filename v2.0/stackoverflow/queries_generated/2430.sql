-- {"query": "2430.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1352} 
with RecursiveCTE as (
  select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount,
    p.OwnerUserId, p.Title,
    ROW_NUMBER() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
  from Posts p
  where p.PostTypeId = 1 and p.CreationDate > current_date - interval '365 days'
),
UserBadges as (
  select b.UserId, b.Class,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges
  from Badges b
  group by b.UserId, b.Class
),
LatestComments as (
  select c.PostId, max(c.CreationDate) as LastCommentDate,
    array_agg(c.Text order by c.CreationDate desc)[:3] as Top3Comments
  from Comments c
  group by c.PostId
),
PostLinkCounts as (
  select pl.PostId,
    count(case when lt.Name = 'Linked' then 1 end) as LinkedCount,
    count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount
  from PostLinks pl
  join LinkTypes lt on pl.LinkTypeId = lt.Id
  group by pl.PostId
), 
PostScores as (
  select v.PostId,
    sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
    sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
  from Votes v
  join VoteTypes vt on v.VoteTypeId = vt.Id
  group by v.PostId
),
OwnerStats as (
  select u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(b.GoldBadges,0) as GoldBadgeCount,
    coalesce(b.SilverBadges,0) as SilverBadgeCount,
    coalesce(b.BronzeBadges,0) as BronzeBadgeCount,
    count(p.Id) filter (where p.PostTypeId=1) as QuestionCount,
    count(p.Id) filter (where p.PostTypeId=2) as AnswerCount,
    avg(p.Score) filter (where p.PostTypeId=1) as AvgQuestionScore,
    avg(p.Score) filter (where p.PostTypeId=2) as AvgAnswerScore
  from Users u
  left join UserBadges b on u.Id = b.UserId
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.GoldBadges, b.SilverBadges, b.BronzeBadges
),
QuestionsWithAnswers as (
  select q.Id as QuestionId, q.Title, q.OwnerUserId, q.CreationDate, q.ViewCount, q.Score as QuestionScore,
    a.Id as AnswerId, a.OwnerUserId as AnswerOwnerUserId, a.Score as AnswerScore,
    rank() over (partition by q.Id order by a.Score desc) as AnswerRank
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
),
AnswerStats as (
  select QuestionId,
    count(*) as AnswerCount,
    sum(case when AnswerScore > 0 then 1 else 0 end) as PositiveAnswerCount,
    max(AnswerScore) as MaxAnswerScore,
    avg(AnswerScore) as AvgAnswerScore
  from QuestionsWithAnswers
  group by QuestionId
),
CloseStats as (
  select ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenCount
  from PostHistory ph
  group by ph.PostId
),
ComplexQuery as (
  select q.Id,
    q.Title,
    q.ViewCount,
    q.Score,
    coalesce(ps.UpVotes,0) as UpVotes,
    coalesce(ps.DownVotes,0) as DownVotes,
    coalesce(pl.LinkedCount,0) as LinkedCount,
    coalesce(pl.DuplicateCount,0) as DuplicateCount,
    coalesce(asr.AnswerCount,0) as AnswerCount,
    coalesce(asr.PositiveAnswerCount,0) as PositiveAnswerCount,
    coalesce(asr.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(asr.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(cs.CloseCount,0) as CloseVotes,
    coalesce(cs.ReopenCount,0) as ReopenVotes,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    u.GoldBadgeCount,
    u.SilverBadgeCount,
    u.BronzeBadgeCount,
    array_to_string(first_value(lc.Top3Comments) over (partition by q.Id), ' | ') as RecentComments,
    case when q.ViewCount > 10000 then 'Very Popular' else 'Normal' end as PopularityFlag,
    q.CreationDate,
    LEAD(q.CreationDate) over (order by q.ViewCount desc) as NextMostViewedCreationDate
  from Posts q
  left join PostScores ps on q.Id = ps.PostId
  left join PostLinkCounts pl on q.Id = pl.PostId
  left join AnswerStats asr on q.Id = asr.QuestionId
  left join CloseStats cs on q.Id = cs.PostId
  left join OwnerStats u on q.OwnerUserId = u.Id
  left join LatestComments lc on q.Id = lc.PostId
  where q.PostTypeId = 1
)
select *
from ComplexQuery
where (PopularityFlag = 'Very Popular' and Score > 10 and CloseVotes = 0)
   or (PopularityFlag = 'Normal' and Score between 5 and 10 and CloseVotes < 2)
union
select *
from ComplexQuery
where OwnerReputation > 100000
order by Score desc, ViewCount desc, CreationDate desc
limit 100;