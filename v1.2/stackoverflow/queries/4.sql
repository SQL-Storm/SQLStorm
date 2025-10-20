with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        cast(r.Path || ' > ' || t2.TagName as varchar(1000)) as Path
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and r.Level < 3
    where t2.IsModeratorOnly = false and t2.IsRequired = false
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        max(u.LastAccessDate) as LastAccess
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9)
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreDenseRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwner,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        q.Tags,
        q.CreationDate as QuestionCreationDate,
        a.CreationDate as AnswerCreationDate,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600.0 as HoursToAccept
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    group by cht.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserEngagement as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.DistinctBadges,0) as DistinctBadges,
        ua.LastAccess,
        (ua.QuestionsAsked + ua.AnswersGiven + ua.CommentsMade) as TotalContributions,
        case when ua.Reputation > 10000 then 'Expert'
             when ua.Reputation > 1000 then 'Intermediate'
             else 'Beginner' end as ReputationLevel
    from UserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
),
RecentHighlyActiveQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        count(distinct c.Id) as CommentCount,
        count(distinct case when v.VoteTypeId = 2 then v.Id end) as UpVotes,
        count(distinct case when v.VoteTypeId = 3 then v.Id end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountySum
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1 and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.Tags, p.CreationDate
    having count(distinct c.Id) > 5 and count(distinct case when v.VoteTypeId = 2 then v.Id end) > 10
),
CombinedResults as (
    select
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.ReputationLevel,
        ues.TotalContributions,
        ues.GoldBadges,
        ues.SilverBadges,
        ues.BronzeBadges,
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags as QuestionTags,
        q.CreationDate as QuestionCreationDate,
        q.CommentCount,
        q.UpVotes,
        q.DownVotes,
        q.BountySum,
        trh.Path as TagHierarchyPath
    from UserEngagement ues
    left join RecentHighlyActiveQuestions q on q.OwnerUserId = ues.UserId
    left join RecursiveTagHierarchy trh on position(trh.TagName in coalesce(q.Tags, '')) > 0
    where ues.TotalContributions > 50
)
select
    cr.CloseReason,
    cr.ClosedPostsCount,
    count(distinct c.Id) as CommentsOnClosedPosts,
    avg(p.Score) as AvgScoreOnClosedPosts,
    max(p.ViewCount) as MaxViewsOnClosedPosts,
    sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as ClosedWithAcceptedAnswerCount,
    (select count(*) from Posts p2 where p2.PostTypeId = 1) as TotalQuestions,
    (select count(*) from Posts p3 where p3.PostTypeId = 2) as TotalAnswers
from CloseReasonCounts cr
left join PostHistory ph on ph.PostId = any(
    select ph2.PostId from PostHistory ph2
    join PostHistoryTypes pht2 on pht2.Id = ph2.PostHistoryTypeId and pht2.Name = 'Post Closed'
    where true
)
left join Posts p on p.Id = ph.PostId and p.ClosedDate is not null
left join Comments c on c.PostId = p.Id
group by cr.CloseReason, cr.ClosedPostsCount
union all
select
    'Summary' as CloseReason,
    null as ClosedPostsCount,
    null as CommentsOnClosedPosts,
    null as AvgScoreOnClosedPosts,
    null as MaxViewsOnClosedPosts,
    null as ClosedWithAcceptedAnswerCount,
    (select count(*) from Posts p2 where p2.PostTypeId = 1),
    (select count(*) from Posts p3 where p3.PostTypeId = 2)
order by ClosedPostsCount desc NULLS LAST;