-- {"query": "2373.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1347} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        coalesce(sum(vtUp.CountVotes),0) as TotalUpVotes,
        coalesce(sum(vtDown.CountVotes),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select PostId, count(*) as CountVotes
        from Votes
        where VoteTypeId = 2 -- UpMod
        group by PostId
    ) vtUp on vtUp.PostId = any(
        select p3.Id from Posts p3 where p3.OwnerUserId = u.Id
    )
    left join (
        select PostId, count(*) as CountVotes
        from Votes
        where VoteTypeId = 3 -- DownMod
        group by PostId
    ) vtDown on vtDown.PostId = any(
        select p4.Id from Posts p4 where p4.OwnerUserId = u.Id
    )
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select
        tag.TagName,
        tag.Count,
        tag.ExcerptPostId,
        ROW_NUMBER() OVER (ORDER BY tag.Count DESC, tag.TagName) as TagRank
    from Tags tag
    where tag.Count > 1000
),
HighScorePosts as (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.PostTypeId,
        case when p.PostTypeId = 1 then 'Question'
             when p.PostTypeId = 2 then 'Answer'
             else 'Other' end as PostTypeName
    from Posts p
    where p.Score > 20
),
PostLinkDuplicates as (
    select pl.PostId, pl.RelatedPostId, u.DisplayName as OwnerName, lt.Name as LinkTypeName
    from PostLinks pl
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    where pl.LinkTypeId = 3 -- Duplicate
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserReputationsChanges as (
    select
        ph.UserId,
        ph.PostId,
        ph.CreationDate,
        lag(ph.CreationDate) over (partition by ph.UserId order by ph.CreationDate) as PrevChangeDate,
        extract(epoch from ph.CreationDate - coalesce(lag(ph.CreationDate) over (partition by ph.UserId order by ph.CreationDate), ph.CreationDate)) as SecondsSinceLastChange
    from PostHistory ph
    where ph.UserId is not null
    order by ph.UserId, ph.CreationDate
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.UserRank,
    tg.TagName as TopTag,
    hsp.Id as HighScorePostId,
    hsp.Title as HighScorePostTitle,
    hsp.Score as HighScorePostScore,
    pl.LinkTypeName as DuplicateLinkType,
    pl.RelatedPostId as DuplicateOfPostId,
    pl.OwnerName as DuplicatePostOwner,
    cq.PostId as ClosedQuestionId,
    cq.CloseReasonName,
    cq.CloseDate,
    urc.SecondsSinceLastChange,
    concat(
        case when ua.Reputation > 10000 then 'High Rep, '
             when ua.Reputation > 1000 then 'Mid Rep, '
             else 'Low Rep, ' end,
        'Questions: ', ua.QuestionCount, ', Answers: ', ua.AnswerCount, ', Badges: ', ua.BadgeCount
    ) as Summary,
    case 
        when ua.QuestionCount = 0 then 'New User'
        when ua.AnswerCount / nullif(ua.QuestionCount,0) > 2 then 'Answer Specialist'
        when ua.QuestionCount / nullif(ua.AnswerCount,0) > 2 then 'Question Specialist'
        else 'Balanced User' 
    end as UserFocus
from RecursiveUserActivity ua
left join TopTags tg on tg.TagRank = (ua.UserRank % 10) + 1
left join LATERAL (
    select * from HighScorePosts hsp where hsp.OwnerUserId = ua.UserId order by hsp.Score desc limit 1
) hsp on true
left join PostLinkDuplicates pl on pl.PostId = hsp.Id
left join LATERAL (
    select * from ClosedQuestionsWithReason cq where cq.PostId = any(
        select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1
    ) order by cq.CloseDate desc limit 1
) cq on true
left join (
    select UserId, avg(SecondsSinceLastChange) as SecondsSinceLastChange
    from UserReputationsChanges
    group by UserId
) urc on urc.UserId = ua.UserId
where ua.Reputation > 500
order by ua.Reputation desc NULLS LAST, ua.UserRank
limit 100;