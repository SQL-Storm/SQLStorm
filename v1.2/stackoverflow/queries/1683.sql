with  
UserActivity AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsPosted,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersPosted,
        avg(coalesce(p.Score,0)) as AvgPostScore,
        rank() over(partition by u.Location order by count(distinct p.Id) desc) as LocationRank,
        cast(min(u.CreationDate) as date) as ActiveStartDate,
        cast(max(u.LastAccessDate) as date) as ActiveEndDate,
        u.Location,
        u.CreationDate,
        u.LastAccessDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000 or u.Location is not null
    group by u.Id, u.DisplayName, u.Location, u.CreationDate, u.LastAccessDate
), 
QuestionLinks as (
    select 
        pl.PostId as QuestionId,
        string_agg(distinct lt.Name, ', ' order by lt.Name) as LinkTypes,
        string_agg(distinct qt.Title, ' || ' order by qt.Title) as LinkedQuestionsTitles
    from PostLinks pl 
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts pt on pt.Id = pl.PostId and pt.PostTypeId = 1
    left join Posts qt on qt.Id = pl.RelatedPostId and qt.PostTypeId = 1
    group by pl.PostId
),
ScoreDensity AS (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        dense_rank() over (order by p.Score desc) as ScoreRank,
        percent_rank() over (order by p.ViewCount) as ViewPercentRank
    from Posts p 
    where p.PostTypeId in (1,2) and p.Score is not null and p.ViewCount is not null
), 
TopAnswerers AS (
    select 
        a.OwnerUserId, 
        p2.PostTypeId,
        count(*) as totalAnswers,
        sum(case when a.Score >= 10 then 1 else 0 end) as AnswersWithHighScore,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    join Posts p2 on p2.Id = a.Id
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId, p2.PostTypeId
),
BadgeSummary AS (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
ClosedQuestionsInfo AS (
    select 
        q.Id,
        q.Title,
        history.Comment as CloseReasonId,
        cr.Name as CloseReasonName,
        q.CreationDate,
        q.ClosedDate,
        extract(epoch from (q.ClosedDate - q.CreationDate)) / 3600.0 as HoursOpenBeforeClose,
        count(distinct ph.Id) FILTER(WHERE ph.PostHistoryTypeId = 11) as TimesReopened
    from Posts q 
    left join PostHistory history 
        on history.PostId = q.Id and history.PostHistoryTypeId = 10
    left join CloseReasonTypes cr 
        on cr.Id = cast(history.Comment as integer)
    left join PostHistory ph 
        on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    where q.PostTypeId = 1 and q.ClosedDate is not null
    group by q.Id, q.Title, history.Comment, cr.Name, q.CreationDate, q.ClosedDate
),
UserCommentsActivity AS (
    select 
        c.UserId,
        coalesce(u.DisplayName, c.UserDisplayName, 'Anonymous') as Split,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as maxCommentDate,
        min(c.CreationDate) as minCommentDate,
        max(c.Score) as maxScore,
        sum(case when c.Score > 0 then 1 else 0 end) as countsPositiveScores
    from Comments c 
    left join Users u on u.Id = c.UserId
    group by c.UserId, coalesce(u.DisplayName, c.UserDisplayName, 'Anonymous')
),
RestrictedPopularity AS (
    select 
        OwnerUserId as uq_UserId,
        row_number() over(order by count(*) desc) AS RestrictedPopularityRanking
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
)

select  
       ua.UserId, 
       ua.DisplayName,
       ua.TotalPosts + coalesce(uc.CommentCount,0) as TotalContributions,
       ua.QuestionsPosted,
       ua.AnswersPosted,
       ta.MaxAnswerScore,
       ta.AvgAnswerScore,
       bs.GoldBadges,
       bs.SilverBadges,
       bs.BronzeBadges,
       rp.RestrictedPopularityRanking,
       case 
            when cq.Id is null then false
            else true 
       end as HasClosedQuestions,
       ql.LinkTypes,
       ql.LinkedQuestionsTitles,
       cq.Title as ClosedQuestionTitle
from UserActivity ua
left join TopAnswerers ta 
  on ta.OwnerUserId = ua.UserId
left join BadgeSummary bs 
  on bs.UserId = ua.UserId
left join UserCommentsActivity uc
  on uc.UserId = ua.UserId
left join RestrictedPopularity rp
  on rp.uq_UserId = ua.UserId
left join ClosedQuestionsInfo cq
  on cq.Id = ua.UserId
left join QuestionLinks ql
  on ql.QuestionId = ua.UserId
;