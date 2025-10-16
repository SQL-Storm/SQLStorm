-- {"query": "342.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1872} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date is not null
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        case 
            when p.ClosedDate is not null then 'Closed'
            else 'Open'
        end as PostStatus
    from Posts p
    where p.PostTypeId = 1
),
AnswerStats as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        (select count(*) from Comments c where c.PostId = a.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as DownVotes
    from Posts a
    where a.PostTypeId = 2
),
QuestionAnswerAggregates as (
    select 
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        q.AcceptedAnswerId,
        q.CommentCount as QuestionCommentCount,
        q.UpVotes as QuestionUpVotes,
        q.DownVotes as QuestionDownVotes,
        q.PostStatus,
        count(a.AnswerId) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(a.UpVotes) as TotalAnswerUpVotes,
        sum(a.DownVotes) as TotalAnswerDownVotes,
        sum(a.CommentCount) as TotalAnswerComments,
        min(a.CreationDate) as FirstAnswerDate,
        max(a.CreationDate) as LastAnswerDate
    from QuestionStats q
    left join AnswerStats a on q.QuestionId = a.QuestionId
    group by 
        q.QuestionId, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.Tags, q.AcceptedAnswerId, q.CommentCount, q.UpVotes, q.DownVotes, q.PostStatus
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesEarned,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    where pl.LinkTypeId = 3
),
RankedQuestions as (
    select 
        qa.*,
        row_number() over (partition by qa.OwnerUserId order by qa.QuestionCreation desc) as RecentQuestionRank,
        rank() over (order by qa.QuestionScore desc) as ScoreRank,
        dense_rank() over (partition by qa.PostStatus order by qa.ViewCount desc) as ViewRankByStatus
    from QuestionAnswerAggregates qa
),
FinalSelection as (
    select 
        rq.QuestionId,
        rq.Title,
        rq.OwnerUserId,
        ua.DisplayName as OwnerDisplayName,
        rq.QuestionCreation,
        rq.QuestionScore,
        rq.ViewCount,
        rq.AnswerCount,
        rq.Tags,
        rq.AcceptedAnswerId,
        rq.QuestionCommentCount,
        rq.QuestionUpVotes,
        rq.QuestionDownVotes,
        rq.PostStatus,
        rq.TotalAnswers,
        rq.MaxAnswerScore,
        rq.AvgAnswerScore,
        rq.TotalAnswerUpVotes,
        rq.TotalAnswerDownVotes,
        rq.TotalAnswerComments,
        rq.FirstAnswerDate,
        rq.LastAnswerDate,
        ua.Reputation as OwnerReputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.BadgesEarned,
        ua.LastBadgeDate,
        tb.BadgeName as TopBadge1,
        (select BadgeName from TopBadges tb2 where tb2.UserId = rq.OwnerUserId and tb2.BadgeRank = 2) as TopBadge2,
        (select BadgeName from TopBadges tb3 where tb3.UserId = rq.OwnerUserId and tb3.BadgeRank = 3) as TopBadge3,
        dl.RelatedPostId as DuplicateOfPostId,
        dl.RelatedPostTitle as DuplicateOfPostTitle
    from RankedQuestions rq
    left join UserActivity ua on rq.OwnerUserId = ua.UserId
    left join TopBadges tb on rq.OwnerUserId = tb.UserId and tb.BadgeRank = 1
    left join DuplicateLinks dl on rq.QuestionId = dl.PostId
    where rq.RecentQuestionRank <= 5
)
select 
    fs.QuestionId,
    fs.Title,
    fs.OwnerUserId,
    coalesce(fs.OwnerDisplayName, 'Unknown') as OwnerDisplayName,
    fs.QuestionCreation,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.Tags,
    fs.AcceptedAnswerId,
    fs.QuestionCommentCount,
    fs.QuestionUpVotes,
    fs.QuestionDownVotes,
    fs.PostStatus,
    fs.TotalAnswers,
    fs.MaxAnswerScore,
    round(fs.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    fs.TotalAnswerUpVotes,
    fs.TotalAnswerDownVotes,
    fs.TotalAnswerComments,
    fs.FirstAnswerDate,
    fs.LastAnswerDate,
    fs.OwnerReputation,
    fs.QuestionsPosted,
    fs.AnswersPosted,
    fs.CommentsMade,
    fs.BadgesEarned,
    fs.LastBadgeDate,
    fs.TopBadge1,
    fs.TopBadge2,
    fs.TopBadge3,
    fs.DuplicateOfPostId,
    fs.DuplicateOfPostTitle,
    case 
        when fs.PostStatus = 'Closed' and fs.DuplicateOfPostId is not null then 'Closed as Duplicate'
        when fs.PostStatus = 'Closed' then 'Closed for Other Reason'
        else 'Open'
    end as DetailedPostStatus,
    length(fs.Title) as TitleLength,
    strpos(lower(fs.Tags), 'sql') > 0 as HasSQLTag,
    case 
        when fs.ViewCount > 10000 then 'High Traffic'
        when fs.ViewCount between 1000 and 10000 then 'Medium Traffic'
        else 'Low Traffic'
    end as TrafficCategory,
    coalesce(fs.TopBadge1, 'None') || ' / ' || coalesce(fs.TopBadge2, 'None') || ' / ' || coalesce(fs.TopBadge3, 'None') as TopBadgesSummary
from FinalSelection fs
order by fs.QuestionCreation desc, fs.QuestionScore desc
limit 50;