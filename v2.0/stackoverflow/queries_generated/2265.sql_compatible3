with recursive RecursiveTagHierarchy as (
  select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 1 as Level
  from Tags t
  where t.IsModeratorOnly = false

  union all

  select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, r.Level + 1
  from Tags t
  join RecursiveTagHierarchy r on t.Id = r.Id and r.Level < 3
),
UserScoreStats as (
  select 
    u.Id as UserId,
    u.DisplayName,
    coalesce(sum(p.Score),0) as TotalPostScore,
    row_number() over (order by coalesce(sum(p.Score),0) desc) as UserRank,
    count(distinct b.Id) as BadgeCount,
    max(b.Class) filter (where b.Class is not null) as MaxBadgeClass,
    max(b.Date) as LastBadgeDate
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
TopQuestions as (
  select p.Id, p.Title, p.Tags, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate,
    row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserQuestionRank
  from Posts p
  where p.PostTypeId = 1 -- questions only
    and p.Score > 0
),
QuestionCloseReasons as (
  select ph.PostId,
    string_agg(distinct crt.Name, ', ') as CloseReasons
  from PostHistory ph
  left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id and ph.PostHistoryTypeId = 10
  where ph.PostHistoryTypeId = 10 -- Post Closed
  group by ph.PostId
),
UserActivityAggregates as (
  select u.Id,
    count(distinct p.Id) as TotalPosts,
    count(distinct c.Id) as TotalComments,
    count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpvotesGiven,
    count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownvotesGiven,
    max(p.LastActivityDate) as LastPostActivity,
    max(c.CreationDate) as LastCommentDate
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Votes v on v.UserId = u.Id
  group by u.Id
),
AnswerRanks as (
  select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId, a.Score,
    rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
    count(*) over (partition by a.ParentId) as NumAnswers
  from Posts a
  where a.PostTypeId = 2
),
HighlyVotedTopAnswers as (
  select ar.AnswerId, ar.QuestionId, ar.OwnerUserId, ar.Score, ar.AnswerRank, ar.NumAnswers, p.Title as QuestionTitle, u.DisplayName as AnswererName
  from AnswerRanks ar
  join Posts p on p.Id = ar.QuestionId
  join Users u on u.Id = ar.OwnerUserId
  where ar.AnswerRank = 1 and ar.Score > 10
),
CombinedUserSummary as (
  select u.Id as UserId, u.DisplayName,
    us.TotalPostScore, us.UserRank, us.BadgeCount, us.MaxBadgeClass,
    ua.TotalPosts, ua.TotalComments, ua.TotalUpvotesGiven, ua.TotalDownvotesGiven,
    q.Id as TopQuestionId, q.Title as TopQuestionTitle, q.Score as TopQuestionScore, q.ViewCount as TopQuestionViews,
    q.AnswerCount as TopQuestionAnswerCount,
    coalesce(qcr.CloseReasons, 'Open') as TopQuestionCloseReasons,
    hta.AnswerId as TopAnswerId, hta.Score as TopAnswerScore, hta.NumAnswers as TopAnswerCount,
    hta.QuestionTitle as TopAnswerQuestionTitle, hta.AnswererName as TopAnswerOwnerName
  from Users u
  left join UserScoreStats us on us.UserId = u.Id
  left join UserActivityAggregates ua on ua.Id = u.Id
  left join TopQuestions q on q.OwnerUserId = u.Id and q.UserQuestionRank = 1
  left join QuestionCloseReasons qcr on qcr.PostId = q.Id
  left join HighlyVotedTopAnswers hta on hta.OwnerUserId = u.Id
)
select cus.UserId, cus.DisplayName,
  cus.TotalPostScore, cus.UserRank, cus.BadgeCount, 
  case cus.MaxBadgeClass
    when 1 then 'Gold'
    when 2 then 'Silver'
    when 3 then 'Bronze'
    else 'None'
  end as HighestBadgeClass,
  cus.TotalPosts, cus.TotalComments, cus.TotalUpvotesGiven, cus.TotalDownvotesGiven,
  cus.TopQuestionId, substring(cus.TopQuestionTitle from 1 for 50) || case when char_length(cus.TopQuestionTitle) > 50 then '...' else '' end as TopQuestionTitle,
  cus.TopQuestionScore, cus.TopQuestionViews, cus.TopQuestionAnswerCount, cus.TopQuestionCloseReasons,
  cus.TopAnswerId, cus.TopAnswerScore, cus.TopAnswerCount, substring(cus.TopAnswerQuestionTitle from 1 for 50) || case when char_length(cus.TopAnswerQuestionTitle) > 50 then '...' else '' end as TopAnswerQuestionTitle,
  cus.TopAnswerOwnerName,
  (coalesce(cus.TotalPostScore,0)*0.4 
   + coalesce(cus.TotalPosts,0)*2 
   + coalesce(cus.BadgeCount,0)*5
   + coalesce(cus.TotalComments,0)*1.5
   + coalesce(cus.TotalUpvotesGiven,0)*0.3 
   - coalesce(cus.TotalDownvotesGiven,0)*0.5 
   + coalesce(cus.TopQuestionScore,0)*3
   + coalesce(cus.TopQuestionViews,0)/1000.0
   + coalesce(cus.TopAnswerScore,0)*4
  ) as EngagementScore
from CombinedUserSummary cus
where cus.TotalPosts > 5
  and (cus.TopQuestionCloseReasons is null or cus.TopQuestionCloseReasons = 'Open')
order by EngagementScore desc, cus.UserRank
limit 25;