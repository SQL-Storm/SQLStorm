-- {"query": "43.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1629} 
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
    join RecursiveTagHierarchy r on t2.Id <> r.Id and not t2.TagName = any(r.Path)
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyGiven,
        max(u.Reputation) as Reputation,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > u.CreationDate
    left join Comments c on c.UserId = u.Id
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 -- BountyStart
    group by u.Id, u.DisplayName
),
PostScoreStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        avg(p.Score) over (partition by p.PostTypeId) as AvgScore,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType
    from Posts p
    where p.PostTypeId in (1,2)
),
AcceptedAnswerInfo as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.AcceptedAnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
TopUsersWithBadges as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        ua.Reputation,
        ua.ReputationRank,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TotalBadges,0) as TotalBadges
    from UserActivity ua
    left join UserBadgeSummary ubs on ua.UserId = ubs.UserId
    where ua.ReputationRank <= 100
),
PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        count(*) over (partition by pl.PostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
),
ComplexPostAnalysis as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        case
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > p.CreationDate) as CommentsAfterPost,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select string_agg(distinct lt.Name, ', ') from PostLinks pl2 join LinkTypes lt on pl2.LinkTypeId = lt.Id where pl2.PostId = p.Id) as LinkTypesInvolved,
        (select count(distinct pl2.RelatedPostId) from PostLinks pl2 where pl2.PostId = p.Id) as RelatedPostsCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankWithinType
    from Posts p
    where p.PostTypeId in (1,2)
)
select
    t.Id as TagId,
    t.TagName,
    t.Count as TagCount,
    t.Level as TagHierarchyLevel,
    array_to_string(t.Path, ' > ') as TagPath,
    c.CloseReason,
    c.ClosedPostsCount,
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionsAsked,
    u.AnswersGiven,
    u.CommentsMade,
    u.TotalBountyGiven,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TotalBadges,
    p.Id as PostId,
    p.Title as PostTitle,
    p.PostStatus,
    p.Score as PostScore,
    p.ViewCount as PostViews,
    p.CommentsAfterPost,
    p.UpVotes,
    p.DownVotes,
    p.LinkTypesInvolved,
    p.RelatedPostsCount,
    p.RankWithinType,
    a.AcceptedAnswerId,
    a.AnswerOwner,
    a.AnswerScore,
    a.AnswerCreationDate,
    pl.DuplicateCount
from RecursiveTagHierarchy t
cross join CloseReasonCounts c
join TopUsersWithBadges u on u.UserId = (
    select OwnerUserId from Posts p2 where p2.Tags like '%' || t.TagName || '%' limit 1
)
join ComplexPostAnalysis p on p.Tags like '%' || t.TagName || '%'
left join AcceptedAnswerInfo a on a.QuestionId = p.Id
left join PostLinkDuplicates pl on pl.PostId = p.Id
where p.RankWithinType <= 10
order by t.Level, c.ClosedPostsCount desc, u.Reputation desc, p.Score desc
limit 100;