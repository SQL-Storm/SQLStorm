-- {"query": "58019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1235} 
WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(b.Id) AS BadgeCount
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class IN (1, 2) AND u.Reputation > 100000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) >= 10
), HighImpactPosts AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.AnswerCount, p.CreationDate,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
           (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id) AS UpVotes,
           (SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id) AS DownVotes
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31' AND p.AnswerCount > 5
), PostClosureInfo AS (
    SELECT ph.PostId, MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
           COUNT(CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN 1 END) AS MigrationCount
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT au.DisplayName, au.Reputation, au.BadgeCount,
       hip.Score AS PostScore, hip.AnswerCount, hip.CommentCount, hip.UpVotes, hip.DownVotes,
       pci.CloseReason, pci.MigrationCount,
       DENSE_RANK() OVER (ORDER BY hip.Score DESC, hip.UpVotes DESC) AS PostRank
FROM ActiveUsers au
JOIN HighImpactPosts hip ON au.Id = hip.OwnerUserId
LEFT JOIN PostClosureInfo pci ON hip.Id = pci.PostId
WHERE pci.CloseReason NOT IN ('101', '102') AND hip.UpVotes > hip.DownVotes
GROUP BY au.DisplayName, au.Reputation, au.BadgeCount, hip.Score, hip.AnswerCount, hip.CommentCount, hip.UpVotes, hip.DownVotes, pci.CloseReason, pci.MigrationCount
HAVING hip.CommentCount >= 5
ORDER BY PostRank, au.Reputation DESC, hip.Score DESC
LIMIT 100;