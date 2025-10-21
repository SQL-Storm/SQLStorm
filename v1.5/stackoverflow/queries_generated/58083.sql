-- {"query": "58083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1414} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(DISTINCT p.Id) AS PostCount,
           COUNT(DISTINCT c.Id) AS CommentCount, COUNT(DISTINCT v.Id) AS VoteCount,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 year'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate > NOW() - INTERVAL '6 months'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,5,8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1,2) AND b.Date > NOW() - INTERVAL '2 years'
    WHERE u.Reputation > 10000 AND u.DownVotes < (u.UpVotes * 0.1)
    GROUP BY u.Id
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
),
ActivePosts AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
           AVG(p.Score) OVER () AS GlobalAvgScore,
           COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId BETWEEN 4 AND 6) AS EditCount
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.Tags LIKE '%<sql>%'
)
SELECT tu.DisplayName, tu.Reputation, ap.Score, ap.ViewCount,
       (ap.Score * 0.5 + ap.ViewCount * 0.3 + ap.AnswerCount * 0.2) AS EngagementScore,
       (tu.PostCount * 0.4 + tu.CommentCount * 0.3 + tu.VoteCount * 0.2 + tu.BadgeCount * 0.1) AS UserActivityIndex,
       ap.EditCount, ap.GlobalAvgScore,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ap.Id AND pl.LinkTypeId = 3) AS DupeLinks,
       (SELECT STRING_AGG(t.TagName, ', ') FROM Tags t WHERE t.Id IN (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))) AND t.Count > 1000) AS PopularTags
FROM TopUsers tu
JOIN ActivePosts ap ON tu.Id = ap.OwnerUserId
WHERE ap.PostRank <= 5 AND ap.Score > (ap.GlobalAvgScore * 1.5)
ORDER BY EngagementScore DESC, UserActivityIndex DESC
LIMIT 100 OFFSET 0;
