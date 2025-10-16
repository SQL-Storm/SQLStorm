-- {"query": "472.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1674} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select 
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.IsModeratorOnly = 0 and t2.Count < r.Count
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as SelfAnsweredCount,
        max(a.CreationDate) as LastAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
UserActivityRank as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as ReputationRank,
        rank() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopQuestionsWithVotes as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        p.OwnerUserId
    from Posts p
    left join (
        select 
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId = 1
),
AcceptedAnswerDetails as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionsWithAcceptedAnswer as (
    select 
        q.Id,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerCreationDate,
        a.AnswerOwnerName,
        a.AnswerOwnerReputation,
        q.CreationDate as QuestionCreationDate
    from Posts q
    left join AcceptedAnswerDetails a on a.QuestionId = q.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId = a.AnswerId
),
CloseReasonSummary as (
    select 
        pht.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory pht
    join CloseReasonTypes crt on crt.Id::text = pht.Comment
    where pht.PostHistoryTypeId = 10
    group by pht.Comment, crt.Name
)
select 
    qwa.Id as QuestionId,
    qwa.Title,
    qwa.QuestionScore,
    qwa.ViewCount,
    qwa.Tags,
    qwa.AnswerId,
    qwa.AnswerScore,
    qwa.AnswerCreationDate,
    qwa.AnswerOwnerName,
    qwa.AnswerOwnerReputation,
    uac.DisplayName as QuestionOwnerName,
    uac.Reputation as QuestionOwnerReputation,
    uac.TotalPosts,
    uac.TotalComments,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TagBasedBadges,
    crs.CloseReasonName,
    crs.CloseCount,
    row_number() over (partition by uac.Id order by qwa.QuestionScore desc) as UserQuestionRank,
    dense_rank() over (order by qwa.AnswerScore desc nulls last) as AnswerScoreRank,
    case 
        when qwa.ViewCount > 10000 then 'High Traffic'
        when qwa.ViewCount between 1000 and 10000 then 'Medium Traffic'
        else 'Low Traffic'
    end as TrafficCategory,
    substring(qwa.Tags from '<([^>]+)>') as FirstTag,
    length(qwa.Title) as TitleLength,
    coalesce(qwa.AnswerScore,0) - qwa.QuestionScore as ScoreDifference,
    (select count(*) from Comments c where c.PostId = qwa.Id and c.CreationDate > qwa.QuestionCreationDate) as CommentsAfterQuestionCreation,
    (select count(*) from Votes v where v.PostId = qwa.Id and v.CreationDate > qwa.QuestionCreationDate and v.VoteTypeId = 2) as UpVotesAfterCreation,
    (select count(*) from Votes v where v.PostId = qwa.Id and v.CreationDate > qwa.QuestionCreationDate and v.VoteTypeId = 3) as DownVotesAfterCreation
from QuestionsWithAcceptedAnswer qwa
left join UserActivityRank uac on uac.Id = qwa.OwnerUserId
left join UserBadgeCounts ubc on ubc.UserId = qwa.OwnerUserId
left join CloseReasonSummary crs on crs.CloseReasonId = (
    select pht.Comment from PostHistory pht where pht.PostId = qwa.Id and pht.PostHistoryTypeId = 10 order by pht.CreationDate desc limit 1
)
where qwa.QuestionScore > 5
order by AnswerScoreRank, qwa.QuestionScore desc
limit 100;