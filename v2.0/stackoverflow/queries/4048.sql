-- {"query": "4048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 971}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostNumberForUser,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS BodyEditCount,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS HasUpvote,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS RollingAvgScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2, 5)
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
      AND (p.Score > 5 OR p.ViewCount > 1000)
    GROUP BY
        p.Id,
        p.PostTypeId,
        pt.Name,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        -- add columns used in window/aggregate contexts that are not aggregated:
        -- ph.PostHistoryTypeId and ph.PostId appear in windowed aggregates via the joined ph rows,
        ph.PostHistoryTypeId,
        ph.PostId,
        -- c.Id and c.PostId used in COUNT OVER via Comments join
        c.Id,
        c.PostId,
        -- v.VoteTypeId and v.PostId used in MAX OVER via Votes join
        v.VoteTypeId,
        v.PostId
),
UserStats AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCountForPost,
    rp.FavoriteCount,
    rp.BodyEditCount,
    CASE WHEN rp.PostNumberForUser <= 5 THEN 'Early Adopter' WHEN rp.PostNumberForUser BETWEEN 6 AND 50 THEN 'Frequent Contributor' ELSE 'Occasional Contributor' END AS UserContributionLevel,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    COALESCE(us.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(us.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(us.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(us.BronzeBadges, 0) AS UserBronzeBadges,
    rp.HasUpvote,
    rp.RollingAvgScore,
    LENGTH(rp.OwnerDisplayName) AS OwnerDisplayNameLength,
    SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 3) AS OwnerDisplayNamePrefix,
    CASE WHEN rp.PostScore > 0 THEN rp.PostViewCount * 1.0 / rp.PostScore ELSE NULL END AS ScoreToViewRatio
FROM RankedPosts rp
LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
WHERE rp.PostScore > ABS(rp.RollingAvgScore) * 0.5
  AND rp.PostTypeName = 'Question'
  AND rp.OwnerDisplayName IS NOT NULL
  AND rp.OwnerDisplayName LIKE '%a%'
ORDER BY rp.PostCreationDate DESC, rp.PostScore DESC
LIMIT 100;