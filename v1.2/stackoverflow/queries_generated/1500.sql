-- {"query": "1500.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1671} 
with
LatestUserActivity as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    case 
      when length(coalesce(u.AboutMe, '')) > 100 then substring(u.AboutMe from 1 for 100) || '...'
      else coalesce(u.AboutMe, '')
    end as AboutPreview,
    count(b.Id) filter(where b.Class = 1) as GoldBadges,
    count(b.Id) filter(where b.Class = 2) as SilverBadges,
    count(b.Id) filter(where b.Class = 3) as BronzeBadges,
    sum(v.VoteCount) as TotalVotesReceived
  from Users u
  left join Badges b on b.UserId = u.Id
  left join (
    select p.OwnerUserId as UserId, count(v.Id) as VoteCount
    from Votes v 
    inner join Posts p on p.Id = v.PostId
    where p.OwnerUserId is not null
    group by p.OwnerUserId
  ) v on v.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
),
QuestionAnswerStats as (
  select
    p.OwnerUserId,
    count(case when p.PostTypeId=1 then 1 end) as QuestionCount,
    count(case when p.PostTypeId=2 then 1 end) as AnswerCount,
    count(case when p.PostTypeId=2 and p.Score >= all (
      select p2.Score 
      from Posts p2
      where p2.PostTypeId=2 and p2.ParentId = p.ParentId
    ) then 1 end) as UserTopAnswers,
    avg(p.Score) filter (where p.PostTypeId=2) as AvgAnswerScore,
    max(p.Score) filter (where p.PostTypeId=2) as MaxAnswerScore
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
PostsWithRecentComments as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.AcceptedAnswerId,
    p.OwnerUserId,
    p.Tags,
    max(c.CreationDate) as LatestCommentDate,
    count(c.Id) as TotalComments
  from Posts p
  left join Comments c on c.PostId = p.Id
  group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.AcceptedAnswerId, p.OwnerUserId, p.Tags
),
RankedAnswers as (
  select
    p.Id,
    p.ParentId as QuestionId,
    p.Score,
    row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
  from Posts p
  where p.PostTypeId = 2
),
QuestionsWithAnswerStats as (
  select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreated,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    a.AnswerCount,
    tuner.AnswerCount as UserAnswerCount,
    tuner.QuestionCount as UserQuestionCount,
    ra.MaxAnswerScore,
    ra.UserTopAnswers,
    pws.LatestCommentDate,
    pws.TotalComments,
    substring(replace(coalesce(q.Tags, ''), '><', ',') from 2 for unlimited) || substring(replace(coalesce(q.Tags, ''), '><', ',') from 2 for unlimited) as NormalizedTags,
    case 
      when q.AcceptedAnswerId is not null then 'YES'
      else 'NO' 
    end as HasAcceptedAnswer
  from Posts q
  left join (
    select ParentId, count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
    group by ParentId
  ) a on a.ParentId = q.Id
  left join QuestionAnswerStats tuner on tuner.OwnerUserId = q.OwnerUserId
  left join RankedAnswers ra on ra.QuestionId = q.Id and ra.AnswerRank = 1
  left join PostsWithRecentComments pws on pws.PostId = q.Id
  where q.PostTypeId = 1
),
DuplicatePosts as (
  select distinct pl.PostId, pl.RelatedPostId, pl.LinkTypeId
  from PostLinks pl
  where pl.LinkTypeId = 3
),
UserPostLinkSummary as (
  select
    u.Id as UserId,
    count(distinct p.Id) as TotalPosts,
    count(distinct case when du.PostId is not null then p.Id else null end) as DupPosts,
    count(distinct case when p.Score >= 10 then p.Id else null end) as HighScorePosts
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join DuplicatePosts du on du.PostId = p.Id
  group by u.Id
)

select 
  lu.Id,
  lu.DisplayName,
  lu.Reputation,
  lu.Location,
  lu.GoldBadges,
  lu.SilverBadges,
  lu.BronzeBadges,
  coalesce(qas.QuestionCount, 0) as TotalQuestions,
  coalesce(qas.AnswerCount, 0) as TotalAnswers,
  coalesce(qas.UserTopAnswers, 0) as AcceptedOrTopAnswers,
  coalesce(ua.HighScorePosts, 0) as HighScorePosts,
  coalesce(lu.TotalVotesReceived, 0) as VotesGot,
  ua.TotalPosts,
  ua.DupPosts,
  string_agg(distinct coalesce(t.TagName, 'NULL'), ', ') within group (order by t.TagName) filter (where t.TagName is not null) as UniqueUserTags,
-- Window functions for advanced usage
  rank() over(order by lu.Reputation desc) as ReputationRank,
  dense_rank() over(order by coalesce(qas.QuestionCount,0) desc) as QuestionActivityRank,
  case when (lu.SilverBadges + lu.GoldBadges) > 0 then round(cast(lu.EffectiveRep as float) / (lu.GoldBadges + lu.SilverBadges), 2) end as EffectiveReputationPerValuedBadge,
-- Complex string expression:
  substring(coalesce(lu.AboutPreview, 'N/A') from 0 for 55) || 
    ' (created ' || to_char(lu.CreationDate, 'YYYY-MM-DD') || ') - loc: ' ||
    coalesce(lu.Location, 'Unknown') as ProfileSnippet
from LatestUserActivity lu
left join QuestionAnswerStats qas on qas.OwnerUserId = lu.Id
left join UserPostLinkSummary ua on ua.UserId = lu.Id
left join (
  select unnest(string_to_array(lower(substring(Coalesce(tags, '') from 2 for length(tags)-2)), '><')) as tag, p.Id
  from Posts p where p.PostTypeId = 1 and tags is not null
) t on t.Id = ua.UserId
where lu.Reputation > 1000 and ua.TotalPosts > 5

union

select 
  ugs.Id,
  ugs.DisplayName || ' (Low activity)' as DisplayName,
  ugs.Reputation,
  ugs.Location,
  0, 0, 0, 0, 0, 0, 0,
  NULL,
  NULL,
  NULL,
  NULL
from Users ugs
where ugs.Reputation <= 1000
order by ReputationRank nulls last, TotalQuestions desc nulls last
limit 50;