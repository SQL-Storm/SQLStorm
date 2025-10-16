-- {"query": "565.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1144} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopUserBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        p.CreationDate as QuestionCreationDate,
        count(distinct a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnswersWithOwner
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
),
QuestionWithComments as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.QuestionScore,
        q.ViewCount,
        q.QuestionCreationDate,
        q.AnswerCount,
        q.MaxAnswerScore,
        q.AvgAnswerScore,
        q.AnswersWithOwner,
        coalesce(c.CommentCount, 0) as CommentCount
    from QuestionAnswerStats q
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = q.QuestionId
),
RankedQuestions as (
    select
        *,
        rank() over (order by QuestionScore desc, AnswerCount desc, CommentCount desc) as QuestionRank
    from QuestionWithComments
),
DuplicateLinks as (
    select pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
),
QuestionsWithDuplicates as (
    select
        q.*,
        d.OriginalQuestionId
    from RankedQuestions q
    left join DuplicateLinks d on q.QuestionId = d.DuplicateQuestionId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(vt.UpVotes) as TotalUpVotes,
        sum(vt.DownVotes) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserRanked as (
    select
        ua.*,
        row_number() over (order by ua.QuestionsPosted desc, ua.AnswersPosted desc, ua.CommentsMade desc) as ActivityRank
    from UserActivity ua
),
FinalResult as (
    select
        q.QuestionRank,
        q.QuestionId,
        q.Title,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.OriginalQuestionId,
        u.DisplayName as QuestionOwner,
        ur.ActivityRank as OwnerActivityRank,
        b.BadgeName as TopBadge,
        b.Class as BadgeClass,
        case 
            when q.OriginalQuestionId is not null then 'Duplicate'
            when q.AnswerCount = 0 then 'Unanswered'
            when q.CommentCount > 10 then 'Highly Commented'
            else 'Normal'
        end as QuestionStatus,
        concat_ws(' | ',
            coalesce(nullif(q.Title, ''), 'No Title'),
            'Score: ' || coalesce(q.QuestionScore::text, '0'),
            'Answers: ' || coalesce(q.AnswerCount::text, '0'),
            'Comments: ' || coalesce(q.CommentCount::text, '0')
        ) as Summary
    from QuestionsWithDuplicates q
    left join Users u on u.Id = q.OwnerUserId
    left join UserRanked ur on ur.UserId = q.OwnerUserId
    left join TopUserBadges b on b.UserId = q.OwnerUserId and b.BadgeRank = 1
)
select *
from FinalResult
where QuestionRank <= 50
order by QuestionRank;