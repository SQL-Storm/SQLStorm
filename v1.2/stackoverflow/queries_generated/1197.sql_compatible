with RecursiveBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class, b.Date,
           dense_rank() over (partition by u.Id order by b.Date desc) as RecentRank
      from Users u
      left join Badges b on u.Id = b.UserId
     where b.Date >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
RecentTopBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
      from RecursiveBadges
     where RecentRank <= 3
),
QuestionStats as (
    select p.Id as QuestionId,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.Tags,
           coalesce(a.AnswerCount, 0) as AnswerCount,
           coalesce(ac.AcceptedAnswerScore, 0) as AcceptedAnswerScore,
           u.Id as OwnerUserId,
           u.DisplayName as OwnerDisplayName,
           u.Reputation,
           rank() over (partition by date_trunc('month', p.CreationDate) order by p.Score desc) as MonthlyScoreRank
      from Posts p
      left join Users u on p.OwnerUserId = u.Id
      left join (
          select ParentId, count(*) as AnswerCount
            from Posts
           where PostTypeId = 2
           group by ParentId
      ) a on p.Id = a.ParentId
      left join (
          select p2.ParentId, max(p2.Score) as AcceptedAnswerScore
            from Posts p2
            where p2.Id in (
                select AcceptedAnswerId from Posts where AcceptedAnswerId is not null
            )
            group by p2.ParentId
      ) ac on p.Id = ac.ParentId
     where p.PostTypeId = 1
       and p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '6 months'
),
DuplicateQuestions as (
    select pl.PostId as DuplicateId, pl.RelatedPostId as OriginalId
      from PostLinks pl
      join LinkTypes lt on pl.LinkTypeId = lt.Id
     where lt.Name = 'Duplicate'
),
QuestionCommentsCount as (
    select c.PostId, count(*) as CommentCount
      from Comments c
      group by c.PostId
),
UserActivity as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
           count(distinct c.Id) as CommentsMade,
           max(p.CreationDate) as LastPostDate
      from Users u
      left join Posts p on u.Id = p.OwnerUserId
      left join Comments c on u.Id = c.UserId
     group by u.Id, u.DisplayName, u.Reputation
),
UserRankings as (
    select UserId,
           QuestionsPosted,
           AnswersPosted,
           CommentsMade,
           Reputation,
           RANK() OVER (ORDER BY QuestionsPosted DESC, AnswersPosted DESC) as ActivityRank
      from UserActivity
),
ClosedQuestions as (
    select p.Id, p.Title, p.ClosedDate, phr.PostHistoryTypeId, crt.Name as CloseReason,
           phr.CreationDate as CloseVoteDate
      from Posts p
      join PostHistory phr on p.Id = phr.PostId and phr.PostHistoryTypeId = 10
      join CloseReasonTypes crt on cast(phr.Comment as integer) = crt.Id
     where p.PostTypeId = 1
       and p.ClosedDate is not null
       and p.ClosedDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
QuestionsWithBadges as (
    select qs.QuestionId, qs.Title, qs.CreationDate, qs.Score, qs.ViewCount, qs.AnswerCount, qs.AcceptedAnswerScore,
           qs.OwnerUserId, qs.OwnerDisplayName, qs.Reputation, qcc.CommentCount,
           array_agg(rb.BadgeName order by rb.Date desc) filter (where rb.UserId = qs.OwnerUserId) as OwnerBadges
      from QuestionStats qs
      left join QuestionCommentsCount qcc on qs.QuestionId = qcc.PostId
      left join RecursiveBadges rb on rb.UserId = qs.OwnerUserId
     group by qs.QuestionId, qs.Title, qs.CreationDate, qs.Score, qs.ViewCount,
              qs.AnswerCount, qs.AcceptedAnswerScore, qs.OwnerUserId, qs.OwnerDisplayName,
              qs.Reputation, qcc.CommentCount
)
select qwb.QuestionId,
       qwb.Title,
       qwb.CreationDate,
       qwb.Score,
       qwb.ViewCount,
       qwb.AnswerCount,
       qwb.AcceptedAnswerScore,
       qwb.OwnerUserId,
       qwb.OwnerDisplayName,
       qwb.Reputation,
       qwb.CommentCount,
       coalesce(array_to_string(qwb.OwnerBadges, ','), 'No Badges') as OwnerBadges,
       coalesce(dq.OriginalId, null) as DuplicateOfQuestionId,
       cq.CloseReason,
       cq.CloseVoteDate,
       ur.QuestionsPosted,
       ur.AnswersPosted,
       ur.CommentsMade,
       ur.Reputation as UserRep,
       ur.ActivityRank,
       ph.LatestEditDate,
       ph.EditCount
  from QuestionsWithBadges qwb
  left join DuplicateQuestions dq on qwb.QuestionId = dq.DuplicateId
  left join ClosedQuestions cq on qwb.QuestionId = cq.Id
  left join UserRankings ur on qwb.OwnerUserId = ur.UserId
  left join (
      select ph.PostId,
             max(ph.CreationDate) as LatestEditDate,
             count(*) as EditCount
        from PostHistory ph
       where ph.PostHistoryTypeId in (4,5,6)
       group by ph.PostId
  ) ph on qwb.QuestionId = ph.PostId
 where (qwb.Score > 10 or qwb.ViewCount > 5000)
   and (ur.ActivityRank <= 100 or ur.ActivityRank is null)
order by qwb.Score desc, qwb.ViewCount desc, ph.EditCount desc
limit 100;