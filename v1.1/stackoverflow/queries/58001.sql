-- {"query": "58001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1269} 
WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 50
),
TopVotedPosts AS (
    SELECT p.Id AS PostId, p.Title, p.Score, p.Tags, v.VoteTypeId, COUNT(v.Id) OVER (PARTITION BY p.Id) AS VoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 AND v.VoteTypeId IN (2, 8, 9)
),
UserBadgeSummary AS (
    SELECT u.Id AS UserId, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
PostHistoryAnalysis AS (
    SELECT ph.PostId, 
           COUNT(DISTINCT ph.UserId) AS UniqueEditors,
           MAX(ph.CreationDate) AS LastEditDate,
           STRING_AGG(DISTINCT pht.Name, ', ') AS HistoryTypes
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7)
    GROUP BY ph.PostId
)
SELECT au.DisplayName, 
       au.Reputation, 
       au.PostCount,
       tvp.Title AS TopPostTitle,
       tvp.Score AS PostScore,
       tvp.VoteCount,
       ARRAY_LENGTH(STRING_TO_ARRAY(REPLACE(REPLACE(tvp.Tags, '<', ''), '>', ','), ','), 1) AS TagCount,
       ubs.GoldBadges,
       ubs.SilverBadges,
       ubs.BronzeBadges,
       pha.UniqueEditors,
       pha.LastEditDate,
       (SELECT COUNT(*) FROM Comments c WHERE c.UserId = au.Id AND c.CreationDate BETWEEN '2023-01-01' AND '2023-12-31') AS CommentCount,
       (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = au.Id AND p2.PostTypeId = 1) AS AvgQuestionScore
FROM ActiveUsers au
JOIN TopVotedPosts tvp ON au.Id = (SELECT OwnerUserId FROM Posts WHERE Id = tvp.PostId)
JOIN UserBadgeSummary ubs ON au.Id = ubs.UserId
LEFT JOIN PostHistoryAnalysis pha ON tvp.PostId = pha.PostId
WHERE au.Reputation > 10000
ORDER BY au.Reputation DESC, tvp.VoteCount DESC, pha.UniqueEditors DESC
LIMIT 100;