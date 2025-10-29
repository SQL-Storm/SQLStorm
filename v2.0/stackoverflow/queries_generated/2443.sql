-- {"query": "2443.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1415} 
with RecursiveUserActivity as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    coalesce(u.Location, 'Unknown') as Location,
    u.CreationDate,
    u.LastAccessDate,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
    count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
    count(distinct b.Id) as BadgeCount,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived
  from
    Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
  group by
    u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate
),
UserActivityRanked as (
  select
    *,
    row_number() over (partition by Location order by Reputation desc nulls last, QuestionCount desc) as LocationRank,
    rank() over (order by Reputation desc nulls last) as GlobalRank
  from RecursiveUserActivity
),
QuestionWithTagStats as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Title,
    array_remove(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'), '') as TagArray
  from Posts p
  where p.PostTypeId = 1
),
TagStats as (
  select
    unnest(TagArray) as Tag,
    count(*) as QuestionCount,
    avg(Score)::numeric(10,2) as AvgScore,
    max(ViewCount) as MaxViewCount
  from QuestionWithTagStats
  group by Tag
),
QuestionAnswers as (
  select
    q.Id as QuestionId,
    count(a.Id) as AnswerCount,
    sum(a.Score) as TotalAnswerScore,
    max(a.Score) as MaxAnswerScore,
    min(a.Score) as MinAnswerScore,
    bool_or(a.Score >= 10) as AnyHighScoreAnswer
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
  group by q.Id
),
TopUsersForPopularTags as (
  select
    ts.Tag,
    ts.QuestionCount,
    ua.Id as UserId,
    ua.DisplayName,
    ua.Reputation,
    row_number() over (partition by ts.Tag order by ua.Reputation desc) as UserTagRank
  from TagStats ts
  join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', ts.Tag, '>%')
  join Users ua on ua.Id = p.OwnerUserId
  group by ts.Tag, ts.QuestionCount, ua.Id, ua.DisplayName, ua.Reputation
),
ClosingStats as (
  select
    p.Id as PostId,
    p.Title,
    p.ClosedDate,
    cht.Name as CloseReason,
    ph.CreationDate as CloseVoteDate,
    u.DisplayName as CloserName,
    (select count(*) from Comments c where c.PostId = p.Id) as CommentCount
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes cht on cht.Id = ph.Comment::int nullif(ph.Comment, '')::int
  left join Users u on u.Id = ph.UserId
  where p.ClosedDate is not null
),
RecentActivity as (
  select
    p.Id as PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    ph.CreationDate as LastHistoryDate,
    ph.PostHistoryTypeId,
    ph.UserId as EditorUserId,
    ph.UserDisplayName as EditorDisplayName,
    row_number() over (partition by p.Id order by ph.CreationDate desc) as RN
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id
),
RecentComments as (
  select
    c.Id,
    c.PostId,
    c.UserId,
    c.UserDisplayName,
    c.CreationDate,
    row_number() over (partition by c.PostId order by c.CreationDate desc) as RN
  from Comments c
)

select
  ua.DisplayName,
  ua.Location,
  ua.Reputation,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.BadgeCount,
  ua.UpVotesReceived,
  ua.DownVotesReceived,
  ts.Tag,
  ts.QuestionCount as TagQuestionCount,
  ts.AvgScore as TagAvgScore,
  ts.MaxViewCount as TagMaxView,
  qa.AnswerCount as AnswersForQuestion,
  qa.TotalAnswerScore,
  qa.MaxAnswerScore,
  qa.MinAnswerScore,
  qa.AnyHighScoreAnswer,
  cu.CloseReason,
  cu.CloserName,
  cu.CommentCount as CloseCommentCount,
  ra.PostHistoryTypeId as LastEditType,
  ra.EditorDisplayName as LastEditor,
  cm.UserDisplayName as LastCommenter,
  cm.CreationDate as LastCommentDate
from
  UserActivityRanked ua
  left join TopUsersForPopularTags tpt on tpt.UserId = ua.Id and tpt.UserTagRank = 1
  left join TagStats ts on ts.Tag = tpt.Tag
  left join Posts p on p.OwnerUserId = ua.Id and p.PostTypeId = 1
  left join QuestionAnswers qa on qa.QuestionId = p.Id
  left join ClosingStats cu on cu.PostId = p.Id
  left join RecentActivity ra on ra.PostId = p.Id and ra.RN = 1
  left join LATERAL (
    select * from RecentComments c where c.PostId = p.Id order by c.CreationDate desc limit 1
  ) cm on true
where
  ua.GlobalRank <= 100
  and (ts.QuestionCount > 100 or ts.QuestionCount is null)
  and (ua.Location is not null and ua.Location <> 'Unknown')
  and (cu.ClosedDate is null or cu.CloseReason not in ('Exact Duplicate', 'Duplicate'))
order by ua.Reputation desc nulls last, ts.QuestionCount desc nulls last
limit 50;