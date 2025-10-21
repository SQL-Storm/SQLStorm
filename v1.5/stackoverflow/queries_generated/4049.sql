-- {"query": "4049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1331} 
with recursive RecursivePosts as (
  select Id, PostTypeId, ParentId, CreationDate, Score, OwnerUserId, Tags, 1 as depth
  from Posts
  where PostTypeId = 1 and Tags is not null and Tags like '%<sql>%'
  union all
  select p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.OwnerUserId, p.Tags, rp.depth + 1
  from Posts p
  inner join RecursivePosts rp on p.ParentId = rp.Id and rp.depth < 3
),
UserBadgeCounts as (
  select UserId, 
    sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
  from Badges
  group by UserId
),
LatestPostHistories as (
  select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
    row_number() over (partition by ph.PostId, ph.PostHistoryTypeId order by ph.CreationDate desc) as rn
  from PostHistory ph
  where ph.PostHistoryTypeId in (4,5,6)
),
FilteredHistories as (
  select PostId, PostHistoryTypeId, CreationDate
  from LatestPostHistories
  where rn = 1
),
UserActivity as (
  select u.Id, u.DisplayName, count(distinct p.Id) as TotalPosts,
    count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
    count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
    count(distinct c.Id) as CommentsMade,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    row_number() over (order by u.Reputation desc) as ReputationRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join UserBadgeCounts ub on ub.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
QuestionsWithAcceptedAnswerInfo as (
  select q.Id, q.Title, q.OwnerUserId, q.AcceptedAnswerId, q.Score as QuestionScore, a.Score as AnswerScore, q.ViewCount,
    -- calculate the ratio of answer score to question score with null safe logic and zero avoiding
    case when q.Score is null or q.Score = 0 then null else 1.0 * coalesce(a.Score,0) / q.Score end as AnswerToQuestionScoreRatio,
    -- array aggregate tags from string
    string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><') as TagArray
  from Posts q
  left join Posts a on q.AcceptedAnswerId = a.Id
  where q.PostTypeId = 1
),
QuestionsWithVotes as (
  select q.Id, 
    count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
    count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
    count(case when v.VoteTypeId = 8 then 1 end) as BountyStarts,
    count(case when v.VoteTypeId = 9 then 1 end) as BountyEnds
  from Posts q
  left join Votes v on v.PostId = q.Id
  where q.PostTypeId = 1
  group by q.Id
),
CombinedQuestions as (
  select q.*, v.UpVotes, v.DownVotes, v.BountyStarts, v.BountyEnds
  from QuestionsWithAcceptedAnswerInfo q
  left join QuestionsWithVotes v on v.Id = q.Id
),
TopContributors as (
  select ua.Id, ua.DisplayName, ua.TotalPosts, ua.Questions, ua.Answers, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ua.ReputationRank
  from UserActivity ua
  where ua.TotalPosts > 100 and ua.ReputationRank <= 50
)
select 
  c.Id as QuestionId,
  c.Title,
  c.OwnerUserId,
  u.DisplayName as OwnerName,
  c.Score as QuestionScore,
  c.AnswerScore,
  c.AnswerToQuestionScoreRatio,
  c.ViewCount,
  c.UpVotes, c.DownVotes, c.BountyStarts, c.BountyEnds,
  array_to_string(c.TagArray, ',') as Tags,
  -- correlated subquery to get count of comments on question
  (select count(*) from Comments cm where cm.PostId = c.Id) as CommentCount,
  -- left join with recursive CTE to find number of answers within depth 3 (including answers to answers)
  (select count(*) from RecursivePosts rp where rp.Id = c.Id or rp.ParentId = c.Id) as RecursiveAnswerCount,
  -- left join user badges
  tb.GoldBadges, tb.SilverBadges, tb.BronzeBadges,
  ta.TotalPosts, ta.Questions as UserQuestions, ta.Answers as UserAnswers,
  -- window function rank over question score desc
  rank() over (order by c.Score desc) as QuestionScoreRank
from CombinedQuestions c
left join Users u on u.Id = c.OwnerUserId
left join TopContributors ta on ta.Id = u.Id
left join UserBadgeCounts tb on tb.UserId = u.Id
where c.AnswerToQuestionScoreRatio is not null
  and (c.UpVotes > 5 or c.BountyStarts > 0)
  and (
    lower(u.Location) like '%united%' 
    or upper(u.DisplayName) like '%DEV%'
    or u.Reputation > 10000
  )
order by QuestionScoreRank asc
limit 100;