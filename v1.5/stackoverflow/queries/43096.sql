WITH HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation, Location
    FROM Users
    WHERE Reputation > 10000
),
QuestionMetrics AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.OwnerUserId, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount,
        COUNT(DISTINCT ph.UserId) AS EditorCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1 AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
UserBadgesCount AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
FinalResults AS (
    SELECT 
        u.DisplayName,
        u.Reputation,
        qm.Title,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount,
        qm.CommentCount,
        qm.FavoriteCount,
        qm.EditorCount,
        b.TotalBadges,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges
    FROM HighReputationUsers u
    JOIN QuestionMetrics qm ON u.Id = qm.OwnerUserId
    LEFT JOIN UserBadgesCount b ON u.Id = b.UserId
    WHERE qm.Score > 50 AND qm.ViewCount > 1000
)
SELECT *
FROM FinalResults
ORDER BY Reputation DESC, TotalBadges DESC
LIMIT 100;