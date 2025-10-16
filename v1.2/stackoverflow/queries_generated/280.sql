-- {"query": "280.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1278} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and not t2.TagName = any(r.Path)
    where r.Level < 3
),
TopUsersWithBadges as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Id) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(b.Id) > 0
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate as QuestionCreation,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by p.Id order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where p.PostTypeId = 1
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as TotalBountyGiven,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
AnswerWithAcceptedFlag as (
    select
        qa.*,
        case when qa.AnswerId = p.AcceptedAnswerId then 1 else 0 end as IsAcceptedAnswer
    from QuestionAnswerStats qa
    join Posts p on p.Id = qa.QuestionId
),
CombinedResults as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionsPosted,
        u.AnswersPosted,
        u.CommentsMade,
        u.TotalBountyGiven,
        qa.QuestionId,
        qa.Title,
        qa.QuestionCreation,
        qa.QuestionScore,
        qa.ViewCount,
        qa.Tags,
        qa.AnswerId,
        qa.AnswerCreation,
        qa.AnswerScore,
        qa.AnswerOwnerId,
        qa.AnswerOwnerName,
        qa.AnswerRank,
        qa.IsAcceptedAnswer,
        crc.CloseReason,
        crc.CloseCount
    from UserActivityWindow u
    left join AnswerWithAcceptedFlag qa on qa.AnswerOwnerId = u.Id
    left join CloseReasonCounts crc on crc.PostId = qa.QuestionId
    where u.UserRank <= 100
)
select distinct
    cr.UserId,
    cr.DisplayName,
    cr.Reputation,
    cr.QuestionsPosted,
    cr.AnswersPosted,
    cr.CommentsMade,
    cr.TotalBountyGiven,
    cr.QuestionId,
    left(cr.Title, 100) as ShortTitle,
    cr.QuestionCreation,
    cr.QuestionScore,
    cr.ViewCount,
    cr.Tags,
    cr.AnswerId,
    cr.AnswerCreation,
    cr.AnswerScore,
    cr.AnswerOwnerName,
    cr.AnswerRank,
    cr.IsAcceptedAnswer,
    coalesce(cr.CloseReason, 'Open') as CloseReason,
    coalesce(cr.CloseCount, 0) as CloseCount,
    -- Complex string expression: extract first tag from Tags array string
    substring(
        regexp_replace(cr.Tags, '^<|>$', '', 'g') from '^[^><]+'
    ) as FirstTag,
    -- Window function: rank of answer score among user's answers
    rank() over (partition by cr.UserId order by cr.AnswerScore desc nulls last) as AnswerScoreRank,
    -- NULL logic: flag if user has no accepted answers
    case when sum(cr.IsAcceptedAnswer) over (partition by cr.UserId) > 0 then 0 else 1 end as HasNoAcceptedAnswer
from CombinedResults cr
where cr.AnswerRank <= 3 or cr.AnswerRank is null
order by cr.Reputation desc, cr.UserId, cr.QuestionCreation desc
limit 200;