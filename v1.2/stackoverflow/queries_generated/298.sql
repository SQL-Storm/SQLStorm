-- {"query": "298.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1455} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and r.Level < 3
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        max(u.LastAccessDate) as LastAccess
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9) -- BountyStart and BountyClose
    group by u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
PostScoresRanked as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRankDense,
        dense_rank() over (partition by p.PostTypeId order by p.ViewCount desc) as ViewRankDense
    from Posts p
    where p.PostTypeId in (1,2) and p.Score is not null
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        q.AcceptedAnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAccept
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.Comment, crt.Name
),
TopTagsWithExcerpt as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(pe.Body, '[No Excerpt]') as ExcerptBody
    from Tags t
    left join Posts pe on pe.Id = t.ExcerptPostId
    where t.Count > 1000
    order by t.Count desc
    limit 10
),
UserBadgeSummary as (
    select
        b.UserId,
        u.DisplayName,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    join Users u on u.Id = b.UserId
    group by b.UserId, u.DisplayName
    having count(*) > 5
),
PostLinkSummary as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(distinct pl.RelatedPostId) as RelatedPostsCount
    from PostLinks pl
    group by pl.PostId
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.TotalBountyGiven,
    ua.LastAccess,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.DistinctBadges,
    ps.ScoreRank,
    ps.ScoreRankDense,
    ps.ViewRankDense,
    coalesce(aas.HoursToAccept, -1) as HoursToAcceptAcceptedAnswer,
    crc.CloseReasonName,
    crc.CloseCount,
    pts.TagName as PopularTag,
    pts.Count as TagCount,
    substring(pts.ExcerptBody from 1 for 100) as TagExcerptSnippet,
    pls.LinkedCount,
    pls.DuplicateCount,
    pls.RelatedPostsCount
from UserActivity ua
left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
left join PostScoresRanked ps on ps.OwnerUserId = ua.UserId and ps.ScoreRank = 1
left join AcceptedAnswerStats aas on aas.QuestionOwner = ua.UserId
left join CloseReasonCounts crc on crc.CloseReasonId = (
    select ph.Comment from PostHistory ph
    where ph.PostId = (
        select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1
        order by p.CreationDate desc limit 1
    )
    and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc limit 1
)
left join TopTagsWithExcerpt pts on pts.TagName = (
    select unnest(string_to_array(substring(ps.Tags from 2 for length(ps.Tags)-2), '><')) limit 1
)
left join PostLinkSummary pls on pls.PostId = (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId order by p.CreationDate desc limit 1
)
where ua.Reputation > 1000
order by ua.Reputation desc
limit 50;