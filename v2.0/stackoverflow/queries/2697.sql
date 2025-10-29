-- {"query": "2697.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1147}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where (b.TagBased = false) or (b.TagBased is null)
),
TopUserPosts as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        p.PostTypeId,
        p.CreationDate,
        p.Tags,
        coalesce(p.Title, '') as Title,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        cr.Name as CloseReason
    from PostHistory ph
    join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id
    where ph.PostHistoryTypeId = 10
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.LastActivityDate) as LastActivity,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
AnswersWithParentInfo as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        q.Title as QuestionTitle,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreated,
        q.CreationDate as QuestionCreated,
        case 
            when a.CreationDate > q.CreationDate then 'Valid Answer Time'
            else 'Answer Before Question Creation'
        end as AnswerTimingValidity
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
),
ComplexStringMetrics as (
    select
        p.Id as PostId,
        length(p.Body) as BodyLength,
        length(regexp_replace(p.Body, '&#?[a-zA-Z0-9]+;', '', 'g')) as BodyLengthWithoutHtmlEntities,
        array_length(string_to_array(coalesce(p.Tags, ''), '><'), 1) as TagCount,
        case when p.Tags is null then 0 else length(p.Tags) end as TagStringLength,
        coalesce(nullif(p.Title, ''), '[No Title]') as SafeTitle,
        p.Score,
        p.ViewCount
    from Posts p
    where p.PostTypeId = 1
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    r.LastActivity,
    r.PostsCount,
    r.CommentsCount,
    b.BadgeName,
    b.Class as BadgeClass,
    tb.PostId as TopPostId,
    tb.Title as TopPostTitle,
    tb.Score as TopPostScore,
    closeinfo.CloseDate,
    closeinfo.CloseReason,
    answers.AnswerId,
    answers.QuestionId,
    answers.QuestionTitle,
    answers.AnswerScore,
    answers.AnswerTimingValidity,
    strmetrics.BodyLength,
    strmetrics.BodyLengthWithoutHtmlEntities,
    strmetrics.TagCount,
    strmetrics.TagStringLength,
    strmetrics.SafeTitle,
    strmetrics.ViewCount,
    rank() over (partition by coalesce(u.Location, '[Unknown]') order by u.Reputation desc) as LocationRepRank,
    (
        select coalesce(count(*), 0) + 
        case when not exists (
            select 1 from Badges b2 where b2.UserId = u.Id and b2.Date > u.CreationDate
        ) then 1 else 0 end
        from Badges b1 where b1.UserId = u.Id and b1.Date > u.CreationDate
    ) as NewBadgesCountAfterCreation
from Users u
left join UserRecentActivity r on u.Id = r.UserId
left join RecursiveUserBadges b on u.Id = b.UserId and b.BadgeRank = 1
left join TopUserPosts tb on u.Id = tb.OwnerUserId and tb.ScoreRank = 1
left join ClosedQuestions closeinfo on closeinfo.PostId = tb.PostId
left join AnswersWithParentInfo answers on answers.AnswerId = tb.PostId and tb.PostTypeId = 2
left join ComplexStringMetrics strmetrics on strmetrics.PostId = tb.PostId
where
    (u.Reputation > 1000 or u.Location is not null)
    and (
        strmetrics.BodyLength > 1000 
        or strmetrics.TagCount > 3
        or closeinfo.CloseDate is not null
    )
group by
    u.Id,
    u.DisplayName,
    u.Reputation,
    r.LastActivity,
    r.PostsCount,
    r.CommentsCount,
    b.BadgeName,
    b.Class,
    tb.PostId,
    tb.Title,
    tb.Score,
    closeinfo.CloseDate,
    closeinfo.CloseReason,
    answers.AnswerId,
    answers.QuestionId,
    answers.QuestionTitle,
    answers.AnswerScore,
    answers.AnswerTimingValidity,
    strmetrics.BodyLength,
    strmetrics.BodyLengthWithoutHtmlEntities,
    strmetrics.TagCount,
    strmetrics.TagStringLength,
    strmetrics.SafeTitle,
    strmetrics.ViewCount,
    u.Location
order by u.Reputation desc, r.LastActivity desc
limit 100;