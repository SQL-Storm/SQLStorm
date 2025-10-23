-- {"query": "946.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1048} 
with RecursiveUserActivity AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        sum(case 
            when v.VoteTypeId = 2 then 1 
            when v.VoteTypeId = 3 then -1 
            else 0 
        end) as VoteScore,
        row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as LocRank
    from users u
    left join posts p on p.OwnerUserId = u.Id
    left join comments c on c.UserId = u.Id
    left join badges b on b.UserId = u.Id
    left join votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, coalesce(u.Location, 'Unknown')
),
LatestPostHistory AS (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
FilteredPostHistory AS (
    select lph.PostId, lph.PostHistoryTypeId, lph.CreationDate, lph.UserId
    from LatestPostHistory lph
    where lph.rn = 1
),
QuestionAnswerPairs AS (
    select q.Id as QuestionId,
           q.Title,
           q.Tags,
           a.Id as AnswerId,
           a.Score as AnswerScore,
           a.OwnerUserId as AnswerUserId,
           a.CreationDate as AnswerDate
    from posts q
    left join posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TagExploded AS (
    select 
        qap.QuestionId, 
        unnest(string_to_array(substring(qap.Tags from 2 for length(qap.Tags)-2), '><')) as Tag,
        qap.AnswerId,
        qap.AnswerScore,
        qap.AnswerUserId,
        qap.AnswerDate,
        qap.Title
    from QuestionAnswerPairs qap
),
AggregatedTagStats AS (
    select Tag,
           count(distinct QuestionId) as QuestionsWithTag,
           count(distinct AnswerId) as AnswersWithTag,
           avg(AnswerScore) filter (where AnswerScore is not null) as AvgAnswerScore,
           max(AnswerScore) filter (where AnswerScore is not null) as MaxAnswerScore
    from TagExploded
    group by Tag
),
TopUsersPerLocation AS (
    select UserId, DisplayName, Reputation, Location, LocRank
    from RecursiveUserActivity
    where LocRank <= 3
),
ClosedDuplicateCounts AS (
    select ph.PostId,
           count(*) filter (where ph.PostHistoryTypeId=10 and ph.Comment = '101') as DuplicateCloseVotes,
           count(*) filter (where ph.PostHistoryTypeId=10 and ph.Comment != '101') as OtherCloseVotes
    from PostHistory ph
    group by ph.PostId
)
select 
    t.Tag,
    t.QuestionsWithTag,
    t.AnswersWithTag,
    round(t.AvgAnswerScore,2) as AvgAnswerScore,
    t.MaxAnswerScore,
    coalesce(dups.DuplicateCloseVotes,0) as DuplicateCloseVotes,
    coalesce(dups.OtherCloseVotes,0) as OtherCloseVotes,
    u.UserId as TopUserId,
    u.DisplayName as TopUserName,
    u.Reputation as TopUserReputation,
    u.Location as UserLocation
from AggregatedTagStats t
left join LATERAL (
    select ru.UserId, ru.DisplayName, ru.Reputation, ru.Location
    from RecursiveUserActivity ru
    join TagExploded te on te.Tag = t.Tag and te.AnswerUserId = ru.UserId
    order by ru.Reputation desc
    limit 1
) u on true
left join ClosedDuplicateCounts dups on dups.PostId = (
    select min(q.Id)
    from posts q
    where q.PostTypeId = 1 and q.Tags like '%' || t.Tag || '%'
)
where t.QuestionsWithTag > 50
order by t.QuestionsWithTag desc, t.Tag
limit 100;