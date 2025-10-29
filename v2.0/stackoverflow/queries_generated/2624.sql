-- {"query": "2624.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1099} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) over (partition by u.Id, b.Class) as BadgeCountPerClass,
        row_number() over (partition by u.Id order by b.Date desc) as rn,
        coalesce(u.Location, 'Unknown') as Location,
        case 
            when u.Reputation > 10000 then 'High'
            when u.Reputation between 1001 and 10000 then 'Medium'
            else 'Low'
        end as ReputationLevel
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
RankedAnswers as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.OwnerUserId as AnswerUserId,
        p.Score,
        p.CreationDate,
        dense_rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as ScoreRank
    from Posts p
    where p.PostTypeId = 2
),
QuestionDetails as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Tags,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        concat_ws(', ',
            substring(q.Tags from 2 for char_length(q.Tags) - 2)
        ) as CleanTags
    from Posts q
    where q.PostTypeId = 1
),
LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Text as HistoryText
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    order by ph.PostId, ph.CreationDate desc
),
CloseReasonsSummary as (
    select
        lph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVoteCount
    from LatestPostHistories lph
    join CloseReasonTypes crt on cast(lph.HistoryText as int) = crt.Id
    group by lph.PostId, crt.Name
),
UserActivityStats as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
),
HighlyVotedAnswers as (
    select a.AnswerId, a.QuestionId, a.AnswerUserId, a.Score, a.CreationDate,
           q.Title as QuestionTitle,
           row_number() over (partition by a.QuestionId order by a.Score desc) as rn
    from RankedAnswers a
    join Posts q on q.Id = a.QuestionId
    where a.ScoreRank = 1
),
CombinedSet as (
    select u.UserId, u.DisplayName, u.ReputationLevel, u.BadgeCountPerClass, ua.QuestionsAsked, ua.AnswersGiven,
           ua.CommentsMade, ua.UpVotesReceived, ua.DownVotesReceived,
           h.AnswerId, h.Score as TopAnswerScore, h.QuestionTitle,
           cr.CloseReasonName,
           case when cr.CloseReasonName is null then 'Open' else cr.CloseReasonName end as PostStatus
    from RecursiveUserBadges u
    left join UserActivityStats ua on u.UserId = ua.UserId
    left join HighlyVotedAnswers h on u.UserId = h.AnswerUserId
    left join CloseReasonsSummary cr on cr.PostId = h.QuestionId
    where u.rn = 1
)
select 
    c.UserId,
    c.DisplayName,
    c.ReputationLevel,
    c.BadgeCountPerClass,
    c.QuestionsAsked,
    c.AnswersGiven,
    c.CommentsMade,
    c.UpVotesReceived,
    c.DownVotesReceived,
    c.AnswerId,
    c.TopAnswerScore,
    substring(c.QuestionTitle from 1 for 50) || case when length(c.QuestionTitle) > 50 then '...' else '' end as ShortQuestionTitle,
    c.PostStatus,
    length(coalesce(c.QuestionTitle, '')) as QuestionTitleLength,
    case
        when c.PostStatus = 'Open' then 'Active'
        else 'Closed'
    end as StatusCategory
from CombinedSet c
where c.BadgeCountPerClass > 5
order by c.UpVotesReceived desc nulls last, c.TopAnswerScore desc nulls last, c.ReputationLevel desc
limit 100;