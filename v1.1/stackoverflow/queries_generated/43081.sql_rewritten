-- {"query": "43081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 561} 
WITH UserReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
RecentActivity AS (
    SELECT 
        p.Id AS PostId,
        COUNT(ph.Id) AS RevisionCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 24)
    GROUP BY p.Id
)
SELECT 
    tq.Id AS QuestionId,
    tq.Title,
    ur.DisplayName AS OwnerDisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.CommentCount,
    tq.FavoriteCount,
    ra.RevisionCount,
    ra.LastEditDate
FROM TopQuestions tq
JOIN UserReputation ur ON tq.OwnerUserId = ur.Id
LEFT JOIN RecentActivity ra ON tq.Id = ra.PostId
WHERE tq.QuestionRank <= 100
ORDER BY tq.Score DESC, tq.ViewCount DESC;