-- {"query": "50074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1159} 

WITH TagStats AS (
    SELECT
        Id AS TagId,
        TagName,
        Count,
        WikiPostId
    FROM Tags
    WHERE Count > 1000 AND IsModeratorOnly = '0'
),
UserActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        AVG(p.CommentCount) AS AvgCommentCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
        AND p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '5 year')
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 10
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(Id) AS TotalBadges
    FROM Badges
    GROUP BY UserId
),
AcceptedAnswerRatio AS (
    SELECT
        a.OwnerUserId AS UserId,
        CAST(COUNT(q.AcceptedAnswerId) AS REAL) / COUNT(a.Id) AS AcceptanceRatio
    FROM Posts a
    JOIN Posts q ON a.Id = q.AcceptedAnswerId
    WHERE a.OwnerUserId IS NOT NULL AND a.PostTypeId = 2
    GROUP BY a.OwnerUserId
    HAVING COUNT(a.Id) > 5
),
PostEdits AS (
    SELECT
        UserId,
        COUNT(*) as EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6) AND UserId IS NOT NULL -- Edit Title, Body, Tags
    GROUP BY UserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.Location,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    COALESCE(aar.AcceptanceRatio, 0) AS AcceptanceRatio,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    pe.EditCount,
    (ua.TotalScore / CAST(ua.TotalPosts AS REAL)) AS AvgScorePerPost,
    (
        u.Reputation * 0.1 +
        ua.TotalScore * 0.2 +
        COALESCE(ua.TotalViewCount, 0) * 0.05 +
        COALESCE(ua.TotalFavoriteCount, 0) * 0.3 +
        ub.GoldBadges * 20 +
        ub.SilverBadges * 10 +
        ub.BronzeBadges * 5 +
        COALESCE(aar.AcceptanceRatio, 0) * 100 +
        (EXTRACT(EPOCH FROM (ua.LastActivityDate - ua.FirstPostDate)) / 86400) * 0.01
    ) AS CalculatedInfluenceScore,
    RANK() OVER (ORDER BY (
        u.Reputation * 0.1 +
        ua.TotalScore * 0.2 +
        COALESCE(ua.TotalViewCount, 0) * 0.05 +
        COALESCE(ua.TotalFavoriteCount, 0) * 0.3 +
        ub.GoldBadges * 20 +
        ub.SilverBadges * 10 +
        ub.BronzeBadges * 5 +
        COALESCE(aar.AcceptanceRatio, 0) * 100 +
        (EXTRACT(EPOCH FROM (ua.LastActivityDate - ua.FirstPostDate)) / 86400) * 0.01
    ) DESC) AS InfluenceRank
FROM Users u
JOIN UserActivity ua ON u.Id = ua.UserId
JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN AcceptedAnswerRatio aar ON u.Id = aar.UserId
LEFT JOIN PostEdits pe ON u.Id = pe.UserId
WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 1)
  AND u.Id IN (
      SELECT DISTINCT p.OwnerUserId
      FROM Posts p
      WHERE p.OwnerUserId IS NOT NULL AND p.Tags LIKE '%' || (SELECT TagName FROM TagStats ORDER BY Count DESC LIMIT 1) || '%'
  )
ORDER BY InfluenceRank ASC
LIMIT 100;

