WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, 1 AS Level, CAST(t.TagName AS varchar(1000)) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count, r.Level + 1, CAST(r.Path || ' > ' || t2.TagName AS varchar(1000))
    FROM Tags t2
    INNER JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count <= r.Count AND r.Level < 3
    WHERE t2.IsModeratorOnly = false AND t2.IsRequired = false
),
RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        COALESCE(p.Title, '') AS Title,
        COALESCE(p.Tags, '') AS Tags,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostRank,
        dense_rank() OVER (ORDER BY p.CreationDate) AS PostCreationRank,
        count(*) OVER (PARTITION BY p.PostTypeId) AS PostTypeCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.CreationDate > TIMESTAMP '2012-01-01'
),
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        count(*) AS TotalBadges,
        count(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        count(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        count(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        max(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserReputationWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        sum(u.Reputation) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningReputationSum,
        avg(u.Reputation) OVER () AS AvgReputation,
        max(u.Reputation) OVER () AS MaxReputation,
        min(u.Reputation) OVER () AS MinReputation
    FROM Users u
),
RecentPostActivity AS (
    SELECT 
        ph.PostId,
        max(ph.CreationDate) AS LastEditDate,
        count(*) AS EditCount,
        sum(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        sum(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes
    FROM PostHistory ph
    WHERE ph.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days')
    GROUP BY ph.PostId
),
UserCommentSummary AS (
    SELECT 
        c.UserId,
        count(distinct c.PostId) AS DistinctPostsCommented,
        count(*) AS TotalComments,
        max(c.CreationDate) AS LastCommentDate,
        avg(length(c.Text)) AS AvgCommentLength
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostsWithLinks AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(distinct pl.RelatedPostId) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
        count(distinct pl.RelatedPostId) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.CreationDate
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    uba.TotalBadges,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    COALESCE(ucs.DistinctPostsCommented, 0) AS DistinctPostsCommented,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    COALESCE(ucs.AvgCommentLength, 0) AS AvgCommentLength,
    p.Id AS TopPostId,
    p.Title AS TopPostTitle,
    p.Score AS TopPostScore,
    p.ViewCount AS TopPostViewCount,
    p.PostTypeId AS TopPostType,
    pr.LastEditDate,
    pr.EditCount,
    pr.CloseVotes,
    pr.ReopenVotes,
    rth.Path AS SampleTagPath,
    CASE 
        WHEN u.Reputation >= uru.AvgReputation THEN 'Above Average' 
        ELSE 'Below Average' 
    END AS ReputationCategory,
    CASE 
        WHEN p.Score > 10 AND p.ViewCount > 1000 THEN 'High Impact' 
        WHEN p.Score BETWEEN 5 AND 10 THEN 'Medium Impact' 
        ELSE 'Low Impact' 
    END AS PostImpactCategory,
    concat_ws(' - ', substring(p.Title FROM 1 FOR 20), substring(COALESCE(p.Tags, '') FROM 1 FOR 20)) AS ShortTitleWithTags
FROM Users u
INNER JOIN RankedPosts p ON p.OwnerUserId = u.Id AND p.UserPostRank = 1
LEFT JOIN UserBadgeAgg uba ON uba.UserId = u.Id
LEFT JOIN UserCommentSummary ucs ON ucs.UserId = u.Id
LEFT JOIN RecentPostActivity pr ON pr.PostId = p.Id
LEFT JOIN RecursiveTagHierarchy rth ON position(rth.TagName IN COALESCE(p.Tags, '')) > 0 AND rth.Level = 1
CROSS JOIN (
    SELECT uru.Id, uru.DisplayName, uru.Reputation, uru.RunningReputationSum, uru.AvgReputation, uru.MaxReputation, uru.MinReputation
    FROM UserReputationWindow uru
    ORDER BY uru.Reputation DESC
    LIMIT 1
) uru
WHERE u.Reputation > (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY Reputation) FROM Users)
AND EXISTS (
    SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.AcceptedAnswerId IS NOT NULL
)
UNION
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS TotalBadges,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS DistinctPostsCommented,
    0 AS TotalComments,
    0 AS AvgCommentLength,
    NULL AS TopPostId,
    NULL AS TopPostTitle,
    NULL AS TopPostScore,
    NULL AS TopPostViewCount,
    NULL AS TopPostType,
    NULL AS LastEditDate,
    NULL AS EditCount,
    NULL AS CloseVotes,
    NULL AS ReopenVotes,
    NULL AS SampleTagPath,
    'Below Average' AS ReputationCategory,
    'Low Impact' AS PostImpactCategory,
    NULL AS ShortTitleWithTags
FROM Users u
WHERE u.Reputation <= (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY Reputation) FROM Users)
EXCEPT
SELECT u.Id, u.DisplayName, u.Reputation, uba.TotalBadges, uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges,
       COALESCE(ucs.DistinctPostsCommented, 0), COALESCE(ucs.TotalComments, 0), COALESCE(ucs.AvgCommentLength, 0),
       p.Id, p.Title, p.Score, p.ViewCount, p.PostTypeId,
       pr.LastEditDate, pr.EditCount, pr.CloseVotes, pr.ReopenVotes,
       rth.Path,
       CASE WHEN u.Reputation >= uru.AvgReputation THEN 'Above Average' ELSE 'Below Average' END,
       CASE WHEN p.Score > 10 AND p.ViewCount > 1000 THEN 'High Impact' WHEN p.Score BETWEEN 5 AND 10 THEN 'Medium Impact' ELSE 'Low Impact' END,
       concat_ws(' - ', substring(p.Title FROM 1 FOR 20), substring(COALESCE(p.Tags, '') FROM 1 FOR 20))
FROM Users u
INNER JOIN RankedPosts p ON p.OwnerUserId = u.Id AND p.UserPostRank = 1
LEFT JOIN UserBadgeAgg uba ON uba.UserId = u.Id
LEFT JOIN UserCommentSummary ucs ON ucs.UserId = u.Id
LEFT JOIN RecentPostActivity pr ON pr.PostId = p.Id
LEFT JOIN RecursiveTagHierarchy rth ON position(rth.TagName IN COALESCE(p.Tags, '')) > 0 AND rth.Level = 1
CROSS JOIN (
    SELECT uru.Id, uru.DisplayName, uru.Reputation, uru.RunningReputationSum, uru.AvgReputation, uru.MaxReputation, uru.MinReputation
    FROM UserReputationWindow uru
    ORDER BY uru.Reputation DESC
    LIMIT 1
) uru
WHERE u.Reputation <= (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY Reputation) FROM Users)
ORDER BY Reputation DESC, UserId ASC
LIMIT 100;