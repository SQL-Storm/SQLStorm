-- {"query": "165.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1794} 
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
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and t.Count < r.Count and t.IsModeratorOnly = 0 and t.IsRequired = 0
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyGiven,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 -- BountyStart
    group by u.Id, u.DisplayName, u.Reputation
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
        avg(p.Score) over (partition by p.PostTypeId) as AvgScoreByType,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRankByType,
        count(*) over (partition by p.OwnerUserId) as PostsByUser
    from Posts p
    where p.PostTypeId in (1,2)
),
AcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.Id as AcceptedAnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAccept
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by cht.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Score, p.ViewCount, p.Tags
    having count(c.Id) > 0
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
UserVotePatterns as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoritesCast,
        count(v.Id) filter (where v.VoteTypeId = 8) as BountiesStarted,
        count(v.Id) filter (where v.VoteTypeId = 9) as BountiesClosed
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.TotalBountyGiven,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.DistinctBadges,
    coalesce(ps.PostTypeId, 0) as SamplePostType,
    coalesce(ps.Score, 0) as SamplePostScore,
    coalesce(ps.ViewCount, 0) as SamplePostViewCount,
    coalesce(ps.AvgScoreByType, 0) as AvgScoreForPostType,
    coalesce(ps.ScoreRankByType, 0) as ScoreRankForPostType,
    coalesce(ps.PostsByUser, 0) as TotalPostsByUser,
    coalesce(ad.HoursToAccept, -1) as AvgHoursToAcceptAnswer,
    crc.CloseReason,
    crc.ClosedPostsCount,
    tth.Level as TagHierarchyLevel,
    tth.Path as TagPath,
    tth.Count as TagCount,
    tth.TagName,
    tpc.CommentCount as TopPostCommentCount,
    tpc.Commenters as TopPostCommenters,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    uvp.UpVotesCast,
    uvp.DownVotesCast,
    uvp.FavoritesCast,
    uvp.BountiesStarted,
    uvp.BountiesClosed
from UserActivity ua
left join UserBadgeSummary ub on ub.UserId = ua.UserId
left join PostScoreStats ps on ps.OwnerUserId = ua.UserId and ps.ScoreRankByType = 1
left join AcceptedAnswerDetails ad on ad.QuestionOwner = ua.UserId
left join CloseReasonCounts crc on crc.CloseReason = (
    select cht.Name from CloseReasonTypes cht
    join PostHistory ph on cast(ph.Comment as int) = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.PostId in (
        select p.Id from Posts p where p.OwnerUserId = ua.UserId
    )
    order by count(ph.PostId) desc limit 1
)
left join RecursiveTagHierarchy tth on tth.TagName = (
    select unnest(string_to_array(substring(ps.Tags from 2 for length(ps.Tags)-2), '><')) limit 1
)
left join TopPostsWithComments tpc on tpc.Id = ps.Id
left join DuplicateLinks dup on dup.PostId = ps.Id
left join UserVotePatterns uvp on uvp.UserId = ua.UserId
where ua.Reputation > 1000
order by ua.Reputation desc
limit 50;