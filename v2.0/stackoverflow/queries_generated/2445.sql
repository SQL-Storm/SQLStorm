-- {"query": "2445.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1561} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.TagBased,
        row_number() over(partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
TopUserBadges as (
    select UserId, DisplayName, BadgeName, Class, TagBased
    from RecursiveUserBadges
    where rn <= 3
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score as QuestionScore,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(vt.UpVotes,0) as UpVotes,
        coalesce(vt.DownVotes,0) as DownVotes,
        count(distinct c.Id) as CommentCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        string_agg(distinct lnk.RelatedPostId::text, ',' order by lnk.RelatedPostId) as LinkedPostIds
    from Posts p
    left join Votes vt on p.Id = vt.PostId and vt.VoteTypeId in (2,3)
    left join Comments c on p.Id = c.PostId
    left join PostHistory ph on p.Id = ph.PostId
    left join PostLinks lnk on p.Id = lnk.PostId and lnk.LinkTypeId = 1
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.AnswerCount, vt.UpVotes, vt.DownVotes
),
AnswerRanks as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        row_number() over(partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
AnswerWithUserBadge as (
    select 
        ar.AnswerId,
        ar.QuestionId,
        ar.AnswerOwnerUserId,
        ar.AnswerScore,
        tub.BadgeName,
        tub.Class as BadgeClass
    from AnswerRanks ar
    left join TopUserBadges tub on ar.AnswerOwnerUserId = tub.UserId
    where ar.AnswerRank <= 5
),
QuestionAcceptedAnswer as (
    select q.Id as QuestionId, q.AcceptedAnswerId, a.Score as AcceptedAnswerScore
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCreated,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCreated,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpvotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownvotesGiven,
        row_number() over(order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join Votes v on u.Id = v.UserId
    group by u.Id, u.DisplayName, u.Reputation
),
TopTagsOnQuestions as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViewCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    having count(*) > 100
),
ClosedQuestionsWithReason as (
    select 
        ph.PostId as QuestionId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        u.DisplayName as ClosedByUser
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId = 10
),
FinalResults as (
    select 
        qs.QuestionId,
        qs.Title,
        qs.CreationDate,
        qs.QuestionScore,
        qs.AnswerCount,
        qs.UpVotes,
        qs.DownVotes,
        qs.CommentCount,
        qs.LinkedPostIds,
        coalesce(qaa.AcceptedAnswerScore,0) as AcceptedAnswerScore,
        string_agg(distinct awb.BadgeName || ' (' || coalesce(nullif(awb.BadgeClass::text,''), 'N/A') || ')', ', ') as TopAnswererBadges,
        uas.QuestionsCreated,
        uas.AnswersCreated,
        uas.CommentsMade,
        uas.UpvotesGiven,
        uas.DownvotesGiven,
        ua.ReputationRank,
        ct.CloseReason,
        ct.CloseDate,
        ct.ClosedByUser
    from QuestionStats qs
    left join QuestionAcceptedAnswer qaa on qs.QuestionId = qaa.QuestionId
    left join AnswerWithUserBadge awb on qs.QuestionId = awb.QuestionId
    left join UserActivitySummary uas on qs.OwnerUserId = uas.UserId
    left join ClosedQuestionsWithReason ct on qs.QuestionId = ct.QuestionId
    left join UserActivitySummary ua on qs.OwnerUserId = ua.UserId
    group by qs.QuestionId, qs.Title, qs.CreationDate, qs.QuestionScore, qs.AnswerCount, qs.UpVotes, qs.DownVotes, qs.CommentCount, qs.LinkedPostIds, qaa.AcceptedAnswerScore, 
             uas.QuestionsCreated, uas.AnswersCreated, uas.CommentsMade, uas.UpvotesGiven, uas.DownvotesGiven, ua.ReputationRank,
             ct.CloseReason, ct.CloseDate, ct.ClosedByUser
)
select 
    fr.QuestionId,
    fr.Title,
    fr.CreationDate,
    fr.QuestionScore,
    fr.AnswerCount,
    fr.UpVotes,
    fr.DownVotes,
    fr.CommentCount,
    fr.LinkedPostIds,
    fr.AcceptedAnswerScore,
    coalesce(fr.TopAnswererBadges,'None') as TopAnswererBadges,
    fr.QuestionsCreated,
    fr.AnswersCreated,
    fr.CommentsMade,
    fr.UpvotesGiven,
    fr.DownvotesGiven,
    fr.ReputationRank,
    coalesce(fr.CloseReason,'Open') as CloseReason,
    fr.CloseDate,
    fr.ClosedByUser
from FinalResults fr
where fr.QuestionScore > 10 
  and (fr.CloseReason is null or fr.CloseReason = 'Open')
  and fr.AnswerCount > 0
order by fr.QuestionScore desc, fr.AnswerCount desc
limit 100;