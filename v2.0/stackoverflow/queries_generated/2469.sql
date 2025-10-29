-- {"query": "2469.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1600} 
with RecursiveRanks as (
  select
    p.Id as PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName as OwnerName,
    row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView,
    dense_rank() over (partition by p.OwnerUserId order by p.CreationDate) as OwnerPostSeq,
    concat(
      coalesce(u.Location, 'Unknown'), ' | ',
      coalesce(u.WebsiteUrl, 'NoWebsite'), ' | ',
      case when p.AcceptedAnswerId is not null then 'HasAcceptedAnswer' else 'NoAcceptedAnswer' end
    ) as OwnerInfoSummary
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId in (1, 2)
),
AcceptedAnswerStats as (
  select 
    pa.ParentId as QuestionId,
    count(pa.Id) as AnswerCount,
    max(pa.Score) as MaxAnswerScore,
    max(case when pa.Id = pq.AcceptedAnswerId then pa.Score else null end) as AcceptedAnswerScore
  from Posts pa
  join Posts pq on pq.Id = pa.ParentId and pq.PostTypeId = 1
  where pa.PostTypeId = 2
  group by pa.ParentId
),
UserBadgeRanks as (
  select
    b.UserId,
    b.Name as BadgeName,
    b.Class,
    row_number() over (partition by b.UserId order by b.Class, b.Date) as BadgeRank,
    case when b.TagBased = 1 then 'Tag' else 'Named' end as BadgeType
  from Badges b
),
CloseReasonsCount as (
  select 
    cht.Name as CloseReason,
    count(distinct ph.PostId) as ClosedPostCount
  from PostHistory ph
    join PostHistoryTypes chtype on chtype.Id = ph.PostHistoryTypeId 
    join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
  where ph.PostHistoryTypeId = 10
  group by cht.Name
),
UserScoreSummary as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    sum(coalesce(p.Score,0)) as TotalPostScore,
    sum(coalesce(vt_count.UpVotes,0)) as TotalUpVotes,
    sum(coalesce(vt_count.DownVotes,0)) as TotalDownVotes,
    count(distinct p.Id) as PostCount
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join (
    select 
      v.PostId,
      sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
      sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
  ) vt_count on vt_count.PostId = p.Id
  group by u.Id, u.DisplayName, u.Reputation
),
TopQuestionsWithAnswers as (
  select 
    q.Id as QuestionId,
    q.Title,
    q.ViewCount,
    q.Score as QuestionScore,
    aa.AnswerCount,
    aa.MaxAnswerScore,
    aa.AcceptedAnswerScore,
    q.Tags,
    array_to_string(array_agg(distinct ltp.Name), ', ') as LinkTypes,
    array_to_string(array_agg(distinct l.PostId), ', ') as LinkedPostIds
  from Posts q
  left join AcceptedAnswerStats aa on aa.QuestionId = q.Id
  left join PostLinks l on l.PostId = q.Id
  left join LinkTypes ltp on l.LinkTypeId = ltp.Id
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.ViewCount, q.Score, aa.AnswerCount, aa.MaxAnswerScore, aa.AcceptedAnswerScore, q.Tags
),
WindowedAnswers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.Score as AnswerScore,
    a.CreationDate,
    u.Id as OwnerUserId,
    u.DisplayName,
    first_value(a.Score) over (partition by a.ParentId order by a.CreationDate) as EarliestAnswerScore,
    lag(a.Score) over (partition by a.ParentId order by a.CreationDate) as PreviousAnswerScore,
    lead(a.Score) over (partition by a.ParentId order by a.CreationDate) as NextAnswerScore,
    count(*) over (partition by a.ParentId) as AnswersPerQuestion
  from Posts a
  left join Users u on a.OwnerUserId = u.Id
  where a.PostTypeId = 2
),
QuestionsWithCloseReasonCount AS (
  select 
    p.Id as QuestionId,
    p.Title,
    count(ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVoteCount
  from Posts p
  left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId = 10
  where p.PostTypeId = 1
  group by p.Id, p.Title
)
select 
  tq.QuestionId,
  tq.Title as QuestionTitle,
  tq.ViewCount,
  tq.QuestionScore,
  coalesce(tq.AnswerCount, 0) as AnswerCount,
  coalesce(tq.MaxAnswerScore, 0) as MaxAnswerScore,
  coalesce(tq.AcceptedAnswerScore, 0) as AcceptedAnswerScore,
  substring(tq.Tags from 2 for char_length(tq.Tags)-2) as TagCharacters,
  tq.LinkTypes,
  tq.LinkedPostIds,
  wc.CloseVoteCount,
  rc.ClosedPostCount as CloseReasonCountExactDuplicate,
  usr.DisplayName as UserWithMostPostsName,
  usr.TotalPostScore,
  usr.Reputation,
  usr.TotalUpVotes,
  usr.TotalDownVotes,
  wa.AnswersPerQuestion,
  avg(wa.AnswerScore) over (partition by wa.QuestionId) as AverageAnswerScore,
  min(wa.AnswerScore) over (partition by wa.QuestionId) as MinAnswerScore,
  max(wa.AnswerScore) over (partition by wa.QuestionId) as MaxAnswerScore,
  max(ubr.Class) filter (where ubr.BadgeType = 'Tag') as MaxBadgeClassForUser
from TopQuestionsWithAnswers tq
left join QuestionsWithCloseReasonCount wc on wc.QuestionId = tq.QuestionId
left join CloseReasonsCount rc on rc.CloseReason = 'Exact Duplicate'
left join UserScoreSummary usr on usr.Id = (
  select OwnerUserId from Posts where Id = tq.QuestionId and OwnerUserId is not null limit 1
)
left join WindowedAnswers wa on wa.QuestionId = tq.QuestionId
left join UserBadgeRanks ubr on ubr.UserId = usr.Id
group by tq.QuestionId, tq.Title, tq.ViewCount, tq.QuestionScore, tq.AnswerCount, tq.MaxAnswerScore, tq.AcceptedAnswerScore, tq.Tags, tq.LinkTypes, 
  tq.LinkedPostIds, wc.CloseVoteCount, rc.ClosedPostCount, usr.DisplayName, usr.TotalPostScore, usr.Reputation, usr.TotalUpVotes, usr.TotalDownVotes,
  wa.AnswersPerQuestion
having count(distinct wa.AnswerId) > 3
order by tq.QuestionScore desc, tq.ViewCount desc
limit 100;