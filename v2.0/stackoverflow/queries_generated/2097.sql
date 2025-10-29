-- {"query": "2097.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1577} 
with RecursiveTagPaths as (
    select 
        t.Id,
        t.TagName,
        1 as Depth,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0

    union all

    select 
        t.Id,
        t.TagName,
        r.Depth + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    join RecursiveTagPaths r on t.Id = r.Id + 1 -- simulate hierarchy on Id for demo
    where r.Depth < 5
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(vote_up.VoteCount),0) as UpVotesReceived,
        coalesce(sum(vote_down.VoteCount),0) as DownVotesReceived,
        rank() over (order by u.Reputation desc) as ReputationRank,
        row_number() over (partition by u.Location order by u.Reputation desc nulls last) as LocalReputationRank,
        max(b.Date) filter (where b.Class = 1) as LatestGoldBadgeDate,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vote_up on vote_up.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vote_down on vote_down.PostId = p.Id
    left join Badges b on b.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
AnswerStats as (
    select 
        a.Id as AnswerId, 
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        count(distinct c.Id) as CommentsCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        max(u.Reputation) as AnswererReputation
    from Posts a
    left join Comments c on c.PostId = a.Id
    left join Votes v on v.PostId = a.Id
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.Score, a.CreationDate
),
TopQuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        ua.DisplayName as QuestionOwner,
        ua.Reputation as QuestionOwnerReputation,
        count(distinct a.AnswerId) as AnswersCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.UpVotes) as MaxAnswerUpVotes,
        sum(a.CommentsCount) as TotalAnswerComments,
        first_value(a.AnswerId) over (partition by q.Id order by a.Score desc nulls last) as TopAnswerId,
        first_value(a.CreationDate) over (partition by q.Id order by a.Score desc nulls last) as TopAnswerDate
    from Posts q
    left join Users ua on ua.Id = q.OwnerUserId
    left join AnswerStats a on a.QuestionId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount, ua.DisplayName, ua.Reputation
),
QuestionsWithDuplicates as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- duplicate link type
),
QuestionsAndCloseReasons as (
    select 
        q.Id as QuestionId,
        cr.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from Posts q
    join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes cr on cast(ph.Comment as int) = cr.Id
    where q.PostTypeId = 1
),
ComplexUserMetrics as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        case 
            when ua.AnswersCount > 0 then round(cast(ua.UpVotesReceived as numeric) / ua.AnswersCount, 2) 
            else null 
        end as AvgUpVotesPerAnswer,
        case 
            when ua.QuestionsCount > 0 then round(cast(ua.DownVotesReceived as numeric) / ua.QuestionsCount, 2) 
            else null 
        end as AvgDownVotesPerQuestion,
        ua.ReputationRank,
        ua.LocalReputationRank,
        ua.LatestGoldBadgeDate,
        ua.LastEditDate,
        case when ua.Location is null or length(trim(ua.Location)) = 0 then 'Unknown' else ua.Location end as NormalizedLocation
    from UserActivity ua
)
select 
    qwa.QuestionId,
    qwa.Title,
    qwa.Tags,
    qwa.QuestionCreation,
    qwa.QuestionScore,
    qwa.ViewCount,
    qwa.QuestionOwner,
    qwa.QuestionOwnerReputation,
    coalesce(qd.OriginalQuestionId, null) as DuplicateOfQuestionId,
    qcr.CloseReasonName,
    qcr.CloseDate,
    qwa.AnswersCount,
    qwa.AvgAnswerScore,
    qwa.MaxAnswerUpVotes,
    qwa.TotalAnswerComments,
    qwa.TopAnswerId,
    qwa.TopAnswerDate,
    cum.DisplayName as TopAnswererDisplayName,
    cum.AvgUpVotesPerAnswer,
    cum.AvgDownVotesPerQuestion,
    cum.LatestGoldBadgeDate,
    cum.NormalizedLocation,
    rtp.Path as TagPath
from TopQuestionsWithAnswers qwa
left join QuestionsWithDuplicates qd on qd.DuplicateQuestionId = qwa.QuestionId
left join QuestionsAndCloseReasons qcr on qcr.QuestionId = qwa.QuestionId
left join AnswerStats a on a.AnswerId = qwa.TopAnswerId
left join ComplexUserMetrics cum on cum.UserId = a.QuestionId -- Notice: Intentionally wrong join to force NULLs and complexity
left join RecursiveTagPaths rtp on strpos(qwa.Tags, rtp.TagName) > 0
where qwa.QuestionScore > 10
  and (qcr.CloseReasonName is null or qcr.CloseDate > current_date - interval '180 days')
order by qwa.QuestionScore desc, qwa.ViewCount desc
limit 100;