-- {"query": "4037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2009} 
with RecursiveTagDepth as (
  select
    t.Id,
    t.TagName,
    1 as Depth,
    array[t.TagName] as Path
  from Tags t
  where t.IsModeratorOnly = 0 and t.IsRequired = 0
  union all
  select
    t2.Id,
    t2.TagName,
    r.Depth + 1,
    r.Path || t2.TagName
  from Tags t2
  join RecursiveTagDepth r on array_position(r.Path, t2.TagName) is null and r.Depth < 3
),
UserBadges as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
    count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
    count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
    sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
PostCloseCounts as (
  select
    p.Id as PostId,
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedDate
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id
  group by p.Id
),
PostVotesAggregates as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId = 5) as Favorites,
    sum(v.BountyAmount) as TotalBounty
  from Votes v
  group by v.PostId
),
TopTaggedQuestions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    max(length(regexp_replace(p.Body, '<[^>]*>', '', 'g'))) as PlainBodyLength,
    unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag
  from Posts p
  where p.PostTypeId = 1
  group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.Tags
),
QuestionsWithUserInfo as (
  select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreation,
    q.Score as QuestionScore,
    q.PlainBodyLength,
    u.Id as UserId,
    u.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    coalesce(pva.UpVotes,0) as QuestionUpVotes,
    coalesce(pva.DownVotes,0) as QuestionDownVotes,
    coalesce(pva.Favorites,0) as QuestionFavorites,
    coalesce(pcc.CloseEvents,0) as CloseCount,
    coalesce(pcc.ReopenEvents,0) as ReopenCount,
    pcc.LastClosedDate,
    pcc.LastReopenedDate,
    q.Tag
  from TopTaggedQuestions q
  left join Users u on u.Id = q.OwnerUserId
  left join UserBadges ub on ub.UserId = u.Id
  left join PostVotesAggregates pva on pva.PostId = q.Id
  left join PostCloseCounts pcc on pcc.PostId = q.Id
  where q.Score >= 0 -- only non-negative scored questions
),
RankedAnswers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.CreationDate as AnswerCreation,
    a.Score as AnswerScore,
    a.OwnerUserId as AnswererId,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScore
  from Posts a
  where a.PostTypeId = 2 -- Answers only
),
AnswererUserStats as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    count(distinct a.Id) as AnswerCount,
    avg(a.Score) as AverageAnswerScore,
    sum(case when a.CreationDate > (current_timestamp - interval '1 year') then 1 else 0 end) as RecentAnswerCount
  from Users u
  left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
  group by u.Id, u.DisplayName, u.Reputation
)
select
  q.QuestionId,
  q.Title,
  substring(q.Title from 1 for 80) || case when length(q.Title) > 80 then '...' else '' end as TitleSnippet,
  q.Tag,
  q.QuestionCreation,
  q.QuestionScore,
  q.PlainBodyLength,
  q.DisplayName as QuestionOwner,
  q.GoldBadges,
  q.SilverBadges,
  q.BronzeBadges,
  q.TagBasedBadges,
  q.QuestionUpVotes,
  q.QuestionDownVotes,
  q.QuestionFavorites,
  q.CloseCount,
  q.ReopenCount,
  q.LastClosedDate,
  q.LastReopenedDate,
  a.AnswerId,
  a.AnswerCreation,
  a.AnswerScore,
  au.DisplayName as AnswerOwner,
  au.Reputation as AnswerOwnerReputation,
  aus.AnswerCount as AnswererTotalAnswers,
  aus.AverageAnswerScore,
  aus.RecentAnswerCount,
  case
    when q.LastClosedDate is not null and q.LastClosedDate > (q.QuestionCreation - interval '30 day') then 'Recently Closed'
    when q.ReopenCount > 0 then 'Reopened'
    else 'Open'
  end as QuestionStatus,
  -- calculate time difference in hours between question and answer creation if answer's rank=1
  case when a.RankByScore = 1 then extract(epoch from(a.AnswerCreation - q.QuestionCreation))/3600 else null end as HoursToTopAnswer,
  -- complex conditional string expression with NULL check
  coalesce(nullif(trim(q.DisplayName),''), 'Anonymous') || ' asked a question tagged [' || q.Tag || ']',
  (
    select count(*)
    from Comments c
    where c.PostId = q.QuestionId
      and c.CreationDate > (q.QuestionCreation - interval '7 day')
      and (c.UserId = q.UserId or c.UserDisplayName = q.DisplayName)
  ) as RecentUserCommentsOnQuestion,
  -- correlated subquery with EXISTS and NULL logic for answers with bounty votes
  exists (
    select 1 from Votes v2
    where v2.PostId = a.AnswerId
      and v2.VoteTypeId = 8
      and v2.BountyAmount is not null
  ) as HasBountyVotesOnAnswer
from QuestionsWithUserInfo q
left join RankedAnswers a on a.QuestionId = q.QuestionId and a.RankByScore = 1
left join Users au on au.Id = a.AnswererId
left join AnswererUserStats aus on aus.UserId = a.AnswererId
where q.Tag in (
  select TagName from RecursiveTagDepth where Depth = 1
)
union
select
  q2.QuestionId,
  q2.Title,
  substring(q2.Title from 1 for 80) || case when length(q2.Title) > 80 then '...' else '' end as TitleSnippet,
  q2.Tag,
  q2.QuestionCreation,
  q2.QuestionScore,
  q2.PlainBodyLength,
  q2.DisplayName as QuestionOwner,
  q2.GoldBadges,
  q2.SilverBadges,
  q2.BronzeBadges,
  q2.TagBasedBadges,
  q2.QuestionUpVotes,
  q2.QuestionDownVotes,
  q2.QuestionFavorites,
  q2.CloseCount,
  q2.ReopenCount,
  q2.LastClosedDate,
  q2.LastReopenedDate,
  null as AnswerId,
  null as AnswerCreation,
  null as AnswerScore,
  null as AnswerOwner,
  null as AnswerOwnerReputation,
  null as AnswererTotalAnswers,
  null as AverageAnswerScore,
  null as RecentAnswerCount,
  'No Answers' as QuestionStatus,
  null as HoursToTopAnswer,
  coalesce(nullif(trim(q2.DisplayName),''), 'Anonymous') || ' asked a question tagged [' || q2.Tag || ']',
  0 as RecentUserCommentsOnQuestion,
  false as HasBountyVotesOnAnswer
from QuestionsWithUserInfo q2
where not exists (
  select 1 from RankedAnswers a2 where a2.QuestionId = q2.QuestionId
)
order by QuestionScore desc, QuestionCreation desc
limit 100;