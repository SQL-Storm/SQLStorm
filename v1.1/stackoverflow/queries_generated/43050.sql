-- {"query": "43050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 654} 

WITH HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation, Location
    FROM Users
    WHERE Reputation > 10000
),
QuestionStats AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(ph.Id) AS EditCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, u.DisplayName, u.Reputation
),
TopEditedQuestions AS (
    SELECT 
        qs.PostId, 
        qs.Title, 
        qs.Score, 
        qs.ViewCount, 
        qs.AnswerCount, 
        qs.CommentCount, 
        qs.FavoriteCount,
        qs.OwnerDisplayName,
        qs.OwnerReputation,
        qs.EditCount
    FROM QuestionStats qs
    ORDER BY qs.EditCount DESC
    LIMIT 100
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    teq.PostId,
    teq.Title,
    teq.Score,
    teq.ViewCount,
    teq.AnswerCount,
    teq.CommentCount,
    teq.FavoriteCount,
    teq.OwnerDisplayName,
    teq.OwnerReputation,
    teq.EditCount,
    hr.Reputation AS HighRepUserReputation,
    hr.DisplayName AS HighRepUserDisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges
FROM TopEditedQuestions teq
JOIN Users hr ON teq.OwnerUserId = hr.Id
LEFT JOIN UserBadgeCounts ub ON teq.OwnerUserId = ub.UserId
WHERE teq.ViewCount > 5000 AND teq.FavoriteCount > 50
ORDER BY teq.ViewCount DESC, teq.Score DESC;
