WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
        STRING_AGG(COALESCE(p.Tags, ''), '; ') AS AllTags,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 AND (u.Location IS NOT NULL OR u.AboutMe LIKE '%SQL%')
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        (SELECT AVG(COALESCE(c.Score, 0)) 
         FROM Comments c 
         WHERE c.PostId = p.Id AND c.Text NOT LIKE '%edit%') AS AvgCommentScore,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevViewCount,
        COALESCE(p.ViewCount - LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) AS ViewGrowth
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 10000
),
MergedData AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.TotalPosts,
        ua.TotalScore,
        ua.AvgViewCount,
        ua.AllTags,
        ua.RankInLocation,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.LatestBadgeDate,
        tq.Title AS TopQuestionTitle,
        tq.ViewCount AS TopQuestionViews,
        tq.AvgCommentScore,
        tq.ViewGrowth
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    LEFT JOIN TopQuestions tq ON ua.UserId = tq.OwnerUserId 
        AND tq.ViewCount = (SELECT MAX(tq2.ViewCount) FROM TopQuestions tq2 WHERE tq2.OwnerUserId = ua.UserId)
    WHERE (bs.GoldBadges IS NOT NULL AND bs.GoldBadges >= 1) OR (tq.AvgCommentScore IS NOT NULL AND tq.AvgCommentScore > 2)
    UNION
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        0 AS TotalPosts,
        0 AS TotalScore,
        0 AS AvgViewCount,
        NULL AS AllTags,
        NULL AS RankInLocation,
        0 AS GoldBadges,
        0 AS SilverBadges,
        NULL AS LatestBadgeDate,
        NULL AS TopQuestionTitle,
        NULL AS TopQuestionViews,
        NULL AS AvgCommentScore,
        NULL AS ViewGrowth
    FROM Users u
    WHERE u.Reputation > 5000 AND u.Id NOT IN (SELECT UserId FROM UserActivity)
)
SELECT 
    md.UserId,
    md.DisplayName,
    md.Reputation,
    md.TotalPosts,
    md.TotalScore,
    COALESCE(md.AvgViewCount, 0) AS AvgViewCount,
    UPPER(COALESCE(SUBSTRING(md.AllTags FROM 1 FOR 50), 'No Tags')) AS TruncatedTags,
    md.RankInLocation,
    COALESCE(md.GoldBadges, 0) + COALESCE(md.SilverBadges, 0) AS TotalBadges,
    md.LatestBadgeDate,
    md.TopQuestionTitle,
    md.TopQuestionViews,
    COALESCE(md.AvgCommentScore, (SELECT AVG(Score) FROM Comments WHERE Score > 0)) AS AdjustedAvgCommentScore,
    SUM(COALESCE(md.ViewGrowth, 0)) OVER (PARTITION BY md.UserId ORDER BY md.TopQuestionViews DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViewGrowth,
    EXISTS (
      SELECT 1 
      FROM Votes v 
      WHERE v.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = md.UserId) 
        AND v.VoteTypeId = 2
    ) AS HasUpvotes
FROM MergedData md
WHERE (COALESCE(md.GoldBadges, 0) + COALESCE(md.SilverBadges, 0)) > 0 OR COALESCE(md.TopQuestionViews, 0) > 50000
GROUP BY
    md.UserId,
    md.DisplayName,
    md.Reputation,
    md.TotalPosts,
    md.TotalScore,
    md.AvgViewCount,
    md.AllTags,
    md.RankInLocation,
    md.GoldBadges,
    md.SilverBadges,
    md.LatestBadgeDate,
    md.TopQuestionTitle,
    md.TopQuestionViews,
    md.AvgCommentScore,
    md.ViewGrowth
ORDER BY md.Reputation DESC, md.TotalPosts DESC;