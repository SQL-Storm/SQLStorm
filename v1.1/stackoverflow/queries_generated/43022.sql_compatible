WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViewCount,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
CommentAnalysis AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY 
        p.Id
),
TopPerformingUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalScore,
        AvgScore,
        MaxViewCount,
        TotalBadges,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        RANK() OVER (ORDER BY TotalScore DESC) AS ScoreRank,
        RANK() OVER (ORDER BY TotalBadges DESC) AS BadgeRank
    FROM 
        UserActivity
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        ph.Comment AS LastEditComment,
        ca.CommentCount,
        ca.AvgCommentLength
    FROM 
        Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            Comment,
            ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
        FROM 
            PostHistory
        WHERE 
            PostHistoryTypeId IN (5, 8)
    ) ph ON p.Id = ph.PostId AND ph.rn = 1
    LEFT JOIN 
        CommentAnalysis ca ON p.Id = ca.PostId
    WHERE 
        p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
)
SELECT 
    tpu.DisplayName,
    tpu.Reputation,
    tpu.TotalPosts,
    tpu.TotalQuestions,
    tpu.TotalAnswers,
    tpu.TotalScore,
    tpu.AvgScore,
    tpu.MaxViewCount,
    tpu.TotalBadges,
    tpu.GoldBadges,
    tpu.SilverBadges,
    tpu.BronzeBadges,
    pp.Title AS MostViewedPost,
    pp.Score AS MostViewedPostScore,
    pp.ViewCount AS MostViewedPostViews,
    pp.LastEditComment,
    pp.CommentCount,
    pp.AvgCommentLength
FROM 
    TopPerformingUsers tpu
JOIN 
    PostPerformance pp ON tpu.UserId = pp.OwnerUserId
WHERE 
    tpu.ScoreRank <= 10 OR tpu.BadgeRank <= 10
ORDER BY 
    tpu.TotalScore DESC, tpu.TotalBadges DESC
LIMIT 10;