-- {"query": "2557.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1493} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class, b.Date,
           row_number() over(partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Id is not null
),
TopUserBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostStats as (
    select p.Id as PostId,
           p.PostTypeId,
           case when p.PostTypeId = 1 then p.Title else null end as QuestionTitle,
           coalesce(p.Score,0) as Score,
           coalesce(p.ViewCount,0) as ViewCount,
           coalesce(p.AnswerCount, 0) as AnswerCount,
           p.OwnerUserId,
           u.DisplayName as OwnerName,
           p.CreationDate,
           p.Tags,
           row_number() over(partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
),
AnswerWithAccepted as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.Score, a.CreationDate as AnswerCreation,
           q.Score as QuestionScore, q.ViewCount as QuestionViews, q.Title as QuestionTitle,
           case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted,
           u.DisplayName as AnswerOwner
    from Posts a
    inner join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
LinkSummary as (
    select pl.PostId, lt.Name as LinkTypeName, count(distinct pl.RelatedPostId) as RelatedCount
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId, lt.Name
),
CloseReasonsCounts as (
    select ph.PostId, crt.Name as CloseReason, count(*) as CloseVoteCount
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    inner join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserCommentAgg as (
    select c.UserId, count(*) as TotalComments,
           sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
           sum(case when c.Score <= 0 or c.Score is null then 1 else 0 end) as NonPositiveComments,
           string_agg(distinct substring(c.Text from 1 for 15), ' || ') as CommentSnippets
    from Comments c
    group by c.UserId
),
QuestionsWithStats as (
    select qs.PostId, 
           qs.QuestionTitle, 
           qs.Score as QuestionScore, 
           qs.ViewCount as QuestionViewCount,
           coalesce(ls.RelatedCount,0) as LinkCount,
           coalesce(crc.CloseVoteCount,0) as CloseVotes,
           coalesce(rcnt.RecentAnswers,0) as RecentAnswers,
           coalesce(acc.AccAnswerCount,0) as AcceptedAnswers,
           qs.Tags
    from PostStats qs
    left join LinkSummary ls on qs.PostId = ls.PostId
    left join CloseReasonsCounts crc on qs.PostId = crc.PostId
    left join (
        select ParentId, count(*) as RecentAnswers 
        from Posts 
        where CreationDate > current_date - interval '30 days' and PostTypeId = 2
        group by ParentId
    ) rcnt on qs.PostId = rcnt.ParentId
    left join (
        select ParentId, count(*) as AccAnswerCount 
        from Posts 
        where AcceptedAnswerId is not null and ParentId is not null
        group by ParentId
    ) acc on qs.PostId = acc.ParentId
    where qs.PostTypeId = 1
),
UserReputationRanks as (
    select Id as UserId, DisplayName, Reputation,
           rank() over(order by Reputation desc) as RepRank
    from Users
),
FinalStats as (
    select qws.PostId, qws.QuestionTitle, qws.QuestionScore, qws.QuestionViewCount, 
           qws.LinkCount, qws.CloseVotes, qws.RecentAnswers, qws.AcceptedAnswers, qws.Tags,
           ur.DisplayName as QuestionOwner, ur.Reputation as OwnerReputation, ur.RepRank,
           ub.BadgeName, ub.Class as BadgeClass,
           ua.TotalComments, ua.PositiveComments, ua.NonPositiveComments, ua.CommentSnippets
    from QuestionsWithStats qws
    left join Posts p on qws.PostId = p.Id
    left join Users ur on p.OwnerUserId = ur.Id
    left join TopUserBadges ub on ub.UserId = ur.Id
    left join UserCommentAgg ua on ua.UserId = ur.Id
    left join UserReputationRanks urr on urr.UserId = ur.Id
    -- Filter to only top 10 questions by score and views combined
    where qws.QuestionScore > 0
),
RankedFinal as (
    select *, 
       row_number() over(partition by QuestionOwner order by QuestionScore desc, QuestionViewCount desc) as OwnerQuestionRank
    from FinalStats
)
select rf.PostId, rf.QuestionTitle,
       rf.QuestionScore, rf.QuestionViewCount, rf.LinkCount, rf.CloseVotes,
       rf.RecentAnswers, rf.AcceptedAnswers,
       coalesce(rf.Tags, '') as Tags,
       rf.QuestionOwner, rf.OwnerReputation, rf.RepRank,
       rf.BadgeName, 
       case rf.BadgeClass
         when 1 then 'Gold'
         when 2 then 'Silver'
         when 3 then 'Bronze'
         else 'None'
       end as BadgeClass,
       rf.TotalComments, rf.PositiveComments, rf.NonPositiveComments,
       rf.CommentSnippets,
       -- Complex calculation involving window functions and NULL logic
       sum(rf.QuestionScore) over(partition by rf.QuestionOwner) as TotalScoreByOwner,
       avg(rf.QuestionViewCount) over(partition by rf.QuestionOwner) as AvgViewsByOwner,
       count(rf.PostId) over(partition by rf.QuestionOwner) as QuestionCountByOwner,
       concat(left(coalesce(rf.QuestionTitle,''), 30), '...', ' [Score:', rf.QuestionScore::text, ']') as ShortTitleSnippet
from RankedFinal rf
where rf.OwnerQuestionRank <= 5
order by rf.OwnerReputation desc, rf.QuestionScore desc, rf.QuestionViewCount desc;