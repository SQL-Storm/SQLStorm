-- {"query": "58042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1380} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.Reputation > 10000
),
UserPosts AS (
    SELECT p.OwnerUserId, p.Id AS PostId, p.Title, p.Score, p.ViewCount, p.Tags,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
           (SELECT SUM(v.VoteTypeId) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
           (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2020-01-01'
),
TagUsage AS (
    SELECT t.TagName, COUNT(pt.PostId) AS UsageCount, pt.OwnerUserId
    FROM Tags t
    JOIN (
        SELECT DISTINCT p.OwnerUserId, REGEXP_REPLACE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><', ',') AS Tag
        FROM UserPosts p
    ) pt ON t.TagName = ANY(STRING_TO_ARRAY(pt.Tag, ','))
    GROUP BY t.TagName, pt.OwnerUserId
)
SELECT tu.DisplayName, tu.GoldBadges, tu.ReputationRank,
       up.PostId, up.Title, up.Score, up.CommentCount, up.Upvotes, up.EditCount,
       STRING_AGG(tu_agg.TagName, ', ' ORDER BY tu_agg.UsageCount DESC) AS TopTags,
       AVG(up.Score) OVER (PARTITION BY tu.Id) AS AvgPostScore,
       MAX(up.ViewCount) OVER () AS MaxGlobalViews
FROM TopUsers tu
JOIN UserPosts up ON tu.Id = up.OwnerUserId
LEFT JOIN TagUsage tu_agg ON tu.Id = tu_agg.OwnerUserId
GROUP BY tu.DisplayName, tu.GoldBadges, tu.ReputationRank, up.PostId, up.Title, up.Score, up.CommentCount, up.Upvotes, up.EditCount
HAVING AVG(up.Score) > 10 AND SUM(up.Upvotes) > 50
ORDER BY tu.ReputationRank, up.Score DESC
LIMIT 100;
