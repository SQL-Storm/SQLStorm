WITH UserAnswerStats AS (
    SELECT
        p_ans.OwnerUserId,
        COUNT(p_ans.Id) AS TotalAnswers,
        SUM(p_ans.Score) AS TotalAnswerScore,
        MIN(p_ans.CreationDate) AS FirstAnswerDate,
        MAX(p_ans.CreationDate) AS LastAnswerDate,
        CAST(SUM(CASE WHEN q.AcceptedAnswerId = p_ans.Id THEN 1 ELSE 0 END) AS numeric) AS TotalAcceptedAnswers,
        AVG(q.ViewCount) AS AvgParentQuestionViews
    FROM Posts p_ans
    INNER JOIN Posts q ON p_ans.ParentId = q.Id
    WHERE p_ans.PostTypeId = 2
      AND p_ans.OwnerUserId IS NOT NULL
      AND p_ans.CreationDate > TIMESTAMP '2020-01-01'
    GROUP BY p_ans.OwnerUserId
    HAVING COUNT(p_ans.Id) > 25
),
UserScoreFactors AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        uas.TotalAnswers,
        uas.TotalAcceptedAnswers / NULLIF(uas.TotalAnswers, 0) AS AcceptanceRate,
        uas.TotalAnswerScore / CAST(uas.TotalAnswers AS numeric) AS AvgAnswerScore,
        EXTRACT(EPOCH FROM (uas.LastAnswerDate - uas.FirstAnswerDate)) / (3600*24) AS ActiveDays,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (CASE WHEN (1 + u.DownVotes) = 0 THEN NULL ELSE LN(1 + u.UpVotes) - LN(1 + u.DownVotes) END) AS VoteRatio,
        COALESCE(uas.AvgParentQuestionViews, 0) AS AvgQuestionViews
    FROM Users u
    INNER JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
    WHERE u.Reputation > 5000
      AND u.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
),
UserRanking AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        AcceptanceRate,
        (
            (AvgAnswerScore * (1 + AcceptanceRate)) +
            (LN(1 + Reputation) * 2) +
            (GoldBadges * 25) +
            (SilverBadges * 10) +
            (VoteRatio * 5) +
            (LN(1 + ActiveDays) * 1.5) +
            (LN(1 + AvgQuestionViews) * 0.5)
        ) AS CompositeScore
    FROM UserScoreFactors
),
RankedUsersWithPosts AS (
    SELECT
        ur.UserId,
        ur.DisplayName,
        ur.Reputation,
        ur.CompositeScore,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.Tags,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        pt.Name AS PostType,
        DENSE_RANK() OVER (ORDER BY ur.CompositeScore DESC, ur.Reputation DESC) AS UserRank,
        ROW_NUMBER() OVER (PARTITION BY ur.UserId ORDER BY p.Score DESC, p.FavoriteCount DESC, p.CreationDate DESC) AS PostRankByScore
    FROM UserRanking ur
    LEFT JOIN Posts p ON ur.UserId = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2)
)
SELECT
    ru.UserRank,
    ru.DisplayName,
    ru.Reputation,
    CAST(ROUND(CAST(ru.CompositeScore AS numeric), 2) AS numeric) AS Score,
    ru.PostType,
    COALESCE(ru.Title, '--- No Title (Answer) ---') AS PostTitle,
    ru.Score AS PostScore,
    ru.CommentCount,
    ru.FavoriteCount,
    ru.CreationDate,
    (SELECT STRING_AGG(b.Name, ', ') FROM (SELECT b.Name FROM Badges b WHERE b.UserId = ru.UserId ORDER BY b.Class, b.Date DESC LIMIT 5) b) AS RecentBadges,
    CASE
        WHEN ru.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = ru.UserId AND p2.PostTypeId = CASE WHEN ru.PostType ~ '^[0-9]+$' THEN CAST(ru.PostType AS integer) ELSE p2.PostTypeId END) THEN 'Above Average'
        WHEN ru.Score < (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = ru.UserId AND p2.PostTypeId = CASE WHEN ru.PostType ~ '^[0-9]+$' THEN CAST(ru.PostType AS integer) ELSE p2.PostTypeId END) THEN 'Below Average'
        ELSE 'Average'
    END AS Performance,
    ru.Tags,
    ru.PostRankByScore
FROM RankedUsersWithPosts ru
WHERE ru.UserRank <= 150 AND ru.PostRankByScore <= 2

UNION ALL

SELECT
    999 AS UserRank,
    'SYSTEM METRICS' AS DisplayName,
    (SELECT AVG(u.Reputation) FROM Users u) AS Reputation,
    0.0 AS Score,
    'SUMMARY' AS PostType,
    'Average Answer Score Across Top Users' AS PostTitle,
    CAST(AVG(p.Score) AS INTEGER) AS PostScore,
    CAST(AVG(p.CommentCount) AS INTEGER) AS CommentCount,
    CAST(AVG(p.FavoriteCount) AS INTEGER) AS FavoriteCount,
    CAST(NULL AS timestamp) AS CreationDate,
    CAST(NULL AS text) AS RecentBadges,
    'N/A' AS Performance,
    CAST(NULL AS text) AS Tags,
    NULL AS PostRankByScore
FROM Posts p
WHERE p.PostTypeId = 2 AND p.OwnerUserId IN (SELECT UserId FROM UserRanking)
ORDER BY UserRank, DisplayName, PostRankByScore;