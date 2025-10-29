-- {"query": "4166.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1207}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) AS CommenterRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id <> -1 AND u.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountForPost,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostScoreRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
),
UserPostSummary AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.UserCreationDate,
        rua.PostCount,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.CommentCount,
        rua.LastPostDate,
        rua.ReputationRank,
        rua.CommenterRank,
        COALESCE(pe.PostCount, 0) AS EngagingPostCount,
        CASE WHEN rua.LastPostDate < (SELECT MIN(CreationDate) FROM Posts) THEN 'Inactive' ELSE 'Active' END AS UserActivityStatus
    FROM RankedUserActivity rua
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(Id) AS PostCount
        FROM Posts
        WHERE Score > 5 OR FavoriteCount > 3 OR ViewCount > 1000
        GROUP BY OwnerUserId
    ) pe ON rua.UserId = pe.OwnerUserId
),
UserBadgeDistribution AS (
    SELECT
        ub.UserId,
        COUNT(CASE WHEN ub.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN ub.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN ub.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges ub
    WHERE ub.Date BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
    GROUP BY ub.UserId
)
SELECT
    ups.DisplayName,
    ups.UserCreationDate,
    ups.Reputation,
    ups.PostCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.CommentCount,
    ups.ReputationRank,
    ups.CommenterRank,
    COALESCE(ubd.GoldBadges, 0) AS GoldBadgesEarned,
    COALESCE(ubd.SilverBadges, 0) AS SilverBadgesEarned,
    COALESCE(ubd.BronzeBadges, 0) AS BronzeBadgesEarned,
    ups.EngagingPostCount,
    ups.UserActivityStatus,
    (
      SELECT pt.Name
      FROM Posts p2
      JOIN PostTypes pt ON pt.Id = p2.PostTypeId
      WHERE p2.OwnerUserId = ups.UserId
      ORDER BY p2.CreationDate DESC
      LIMIT 1
    ) AS LastPostType,
    CASE
        WHEN ups.Reputation > 100000 THEN 'High Reputation'
        WHEN ups.Reputation BETWEEN 10000 AND 100000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationLevel,
    COALESCE(ups.LastPostDate, DATE '1900-01-01') AS LastPostActivityDate
FROM UserPostSummary ups
LEFT JOIN UserBadgeDistribution ubd ON ups.UserId = ubd.UserId
WHERE ups.PostCount > 10
ORDER BY ups.ReputationRank, ups.CommenterRank DESC
LIMIT 100;