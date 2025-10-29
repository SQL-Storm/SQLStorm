-- {"query": "2164.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1518} 
with UserBadgeCounts as (
  select 
    u.Id as UserId,
    u.DisplayName,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    rank() over (order by u.Reputation desc) as ReputationRank
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
PostAggregates as (
  select
    p.Id as PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    -- Extract tags into array for filtering
    string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><') as TagArray,
    -- Count of comments per post via correlated subquery
    (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
    -- Count of distinct users who commented on this post
    (select count(distinct c.UserId) from Comments c where c.PostId = p.Id and c.UserId is not null) as DistinctCommenters,
    -- Average score of answers if this is question (PostTypeId=1)
    case when p.PostTypeId = 1 then 
      (select avg(coalesce(a.Score,0)) from Posts a where a.ParentId = p.Id)
    else null end as AvgAnswerScore
  from Posts p
  where p.PostTypeId in (1,2)
),
RecentPostHistoryEdited as (
  select
    ph.PostId,
    max(ph.CreationDate) as LastEditDate,
    max(case when ph.PostHistoryTypeId in (4,5,6) then ph.UserId else null end) as LastEditorId -- type 4=edit title,5=edit body,6=edit tags
  from PostHistory ph
  group by ph.PostId
),
PostVotesCounts as (
  select 
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes, 
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId = 5) as FavoriteVotes
  from Votes v
  group by v.PostId
),
QuestionsWithAnswersAndDuplicates as (
  select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    q.Tags,
    pa.PostTypeId,
    coalesce(pa.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(pvc.UpVotes,0) as QuestionUpVotes,
    coalesce(pvc.DownVotes,0) as QuestionDownVotes,
    coalesce(pvc.FavoriteVotes,0) as QuestionFavoriteVotes,
    -- Aggregate on answers
    (select count(a.Id) from Posts a where a.ParentId = q.Id and a.PostTypeId=2) as AnswerCount,
    (select avg(a.Score) from Posts a where a.ParentId = q.Id and a.PostTypeId=2) as AvgAnswerScore,
    (select count(distinct pl.RelatedPostId) from PostLinks pl where pl.PostId = q.Id and pl.LinkTypeId = 3) as DuplicateCount,
    -- Detect if question is closed recently using PostHistory
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10) as LastClosedDate
  from Posts q
  left join PostAggregates pa on pa.PostId = q.Id
  left join PostVotesCounts pvc on pvc.PostId = q.Id
  where q.PostTypeId = 1
),
RankedQuestionsWithUsers as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    q.CreationDate,
    q.ViewCount,
    q.AnswerCount,
    q.AvgAnswerScore,
    q.DuplicateCount,
    q.LastClosedDate,
    q.QuestionScore,
    q.QuestionUpVotes,
    q.QuestionDownVotes,
    q.QuestionFavoriteVotes,
    -- Window functions for ranking within each tag - unnest tags first
    unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as Tag
  from QuestionsWithAnswersAndDuplicates q
  left join Users u on u.Id = q.OwnerUserId
),
TaggedQuestionRanks as (
  select
    *,
    rank() over (partition by Tag order by QuestionScore desc, ViewCount desc, AnswerCount desc) as TagRank,
    row_number() over (partition by Tag order by QuestionScore desc, ViewCount desc) as RowNum
  from RankedQuestionsWithUsers
),
TopTaggedQuestions as (
  select * from TaggedQuestionRanks where TagRank <= 5
),
ClosedDuplicateQuestionDetails as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    coalesce(q.LastClosedDate, timestamp '1970-01-01') as ClosedDate,
    q.DuplicateCount,
    q.AnswerCount,
    q.QuestionScore,
    u.DisplayName,
    u.Reputation
  from QuestionsWithAnswersAndDuplicates q
  left join Users u on u.Id = q.OwnerUserId
  where q.LastClosedDate is not null and q.DuplicateCount > 0
),
FinalSummary as (
  select
    t.Tag,
    t.QuestionId,
    t.Title,
    t.DisplayName as OwnerName,
    t.Reputation as OwnerReputation,
    t.QuestionScore,
    t.ViewCount,
    t.AnswerCount,
    t.AvgAnswerScore,
    t.DuplicateCount,
    case when t.LastClosedDate is null then 'Open' else 'Closed' end as Status,
    t.LastClosedDate,
    row_number() over (partition by t.Tag order by t.QuestionScore desc) as ScoreRankWithinTag,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges
  from TopTaggedQuestions t
  left join UserBadgeCounts ubc on ubc.UserId = t.OwnerUserId
)
select * from FinalSummary
union
select 
  'ClosedDuplicates' as Tag,
  cd.QuestionId,
  cd.Title,
  cd.DisplayName,
  cd.Reputation,
  cd.QuestionScore,
  null as ViewCount,
  cd.AnswerCount,
  null as AvgAnswerScore,
  cd.DuplicateCount,
  'Closed' as Status,
  cd.ClosedDate,
  null as ScoreRankWithinTag,
  null as GoldBadges,
  null as SilverBadges,
  null as BronzeBadges
from ClosedDuplicateQuestionDetails cd
order by Tag, ScoreRankWithinTag nulls last, QuestionScore desc, QuestionId
limit 100;