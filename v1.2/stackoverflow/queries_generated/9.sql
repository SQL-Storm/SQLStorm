-- {"query": "9.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1595} 
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
    join RecursiveTagHierarchy r on t2.Id = r.Id + 1
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
        count(distinct b.Id) as BadgesEarned,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9) -- BountyStart and BountyClose
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
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank,
        avg(p.Score) over (partition by p.OwnerUserId) as AvgUserPostScore,
        count(*) over (partition by p.OwnerUserId) as UserPostCount
    from Posts p
    where p.PostTypeId in (1,2)
),
TopScoringPosts as (
    select
        ps.Id,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.Tags,
        ps.CreationDate,
        ps.AvgUserPostScore,
        ps.UserPostCount,
        u.DisplayName as OwnerName,
        case
            when ps.Score > 100 then 'High'
            when ps.Score between 50 and 100 then 'Medium'
            else 'Low'
        end as ScoreCategory
    from PostScoreStats ps
    join Users u on u.Id = ps.OwnerUserId
    where ps.ScoreRank <= 5
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
UserBadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ') as BadgeNames
    from Badges b
    group by b.UserId, b.Class
),
UserRankings as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.BadgesEarned,
        ua.TotalBountyGiven,
        ua.LastPostDate,
        ua.FirstPostDate,
        coalesce(ubs_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubs_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubs_bronze.BadgeCount,0) as BronzeBadges,
        rank() over (order by ua.Reputation desc) as ReputationRank,
        rank() over (order by ua.QuestionsAsked desc) as QuestionsRank,
        rank() over (order by ua.AnswersGiven desc) as AnswersRank
    from UserActivity ua
    left join UserBadgeSummary ubs_gold on ubs_gold.UserId = ua.UserId and ubs_gold.Class = 1
    left join UserBadgeSummary ubs_silver on ubs_silver.UserId = ua.UserId and ubs_silver.Class = 2
    left join UserBadgeSummary ubs_bronze on ubs_bronze.UserId = ua.UserId and ubs_bronze.Class = 3
)
select
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.ReputationRank,
    ur.QuestionsAsked,
    ur.QuestionsRank,
    ur.AnswersGiven,
    ur.AnswersRank,
    ur.CommentsMade,
    ur.BadgesEarned,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.TotalBountyGiven,
    ur.FirstPostDate,
    ur.LastPostDate,
    tsp.Id as TopPostId,
    tsp.Score as TopPostScore,
    tsp.ViewCount as TopPostViews,
    tsp.ScoreCategory,
    tsp.Tags as TopPostTags,
    cq.PostId as ClosedQuestionId,
    cq.CloseDate,
    cq.CloseReason,
    cq.ClosedByUserName,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.RelatedPostTitle as DuplicateOfPostTitle,
    string_agg(distinct rth.TagName, ' > ' order by rth.Level) as TagHierarchyPath
from UserRankings ur
left join TopScoringPosts tsp on tsp.OwnerUserId = ur.UserId
left join ClosedQuestionsWithReasons cq on cq.PostId = tsp.Id
left join DuplicateLinks dl on dl.PostId = tsp.Id
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(tsp.Tags,''), '><'))
where ur.Reputation > 1000
group by
    ur.UserId, ur.DisplayName, ur.Reputation, ur.ReputationRank,
    ur.QuestionsAsked, ur.QuestionsRank, ur.AnswersGiven, ur.AnswersRank,
    ur.CommentsMade, ur.BadgesEarned, ur.GoldBadges, ur.SilverBadges, ur.BronzeBadges,
    ur.TotalBountyGiven, ur.FirstPostDate, ur.LastPostDate,
    tsp.Id, tsp.Score, tsp.ViewCount, tsp.ScoreCategory, tsp.Tags,
    cq.PostId, cq.CloseDate, cq.CloseReason, cq.ClosedByUserName,
    dl.RelatedPostId, dl.RelatedPostTitle
order by ur.ReputationRank
limit 100;