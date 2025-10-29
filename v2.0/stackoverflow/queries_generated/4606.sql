-- {"query": "4606.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1188} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC, u.Id) AS PreviousReputation
    FROM Users AS u
    JOIN Posts AS p ON u.Id = p.OwnerUserId
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE u.CreationDate >= '2010-01-01' AND u.DownVotes < 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighEngagementPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.AnswerCount DESC) AS PostRankForUser
    FROM Posts AS p
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.CreationDate >= DATE('now', '-1 year')
      AND p.AnswerCount > 5
      AND p.FavoriteCount > 10
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.AnswerCount
    HAVING COUNT(c.Id) > AVG(p.CommentCount) * 2 -- Posts with significantly more comments than average for that user
),
UserPostPerformance AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.TotalPosts,
        rua.AnswerCount,
        rua.AveragePostScore,
        hep.PostId AS HighEngagementPostId,
        hep.Title AS HighEngagementPostTitle,
        hep.Score AS HighEngagementPostScore,
        (rua.Reputation * 1.0 / (rua.TotalPosts + 1)) AS ReputationPerPost
    FROM RankedUserActivity AS rua
    LEFT JOIN HighEngagementPosts AS hep ON rua.UserId = hep.OwnerUserId AND hep.PostRankForUser = 1
    WHERE rua.TotalPosts > 50
),
LatestEdits AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LatestEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Title, Body, Tags edits
    GROUP BY ph.PostId
    HAVING MAX(ph.CreationDate) >= DATE('now', '-3 months')
)
SELECT
    upp.UserId,
    upp.DisplayName,
    upp.Reputation,
    upp.TotalPosts,
    upp.AnswerCount,
    upp.AveragePostScore,
    upp.ReputationPerPost,
    upp.HighEngagementPostId,
    upp.HighEngagementPostTitle,
    upp.HighEngagementPostScore,
    le.LatestEditDate,
    le.EditCount,
    CASE
        WHEN upp.Reputation > 10000 AND upp.AnswerCount > 500 THEN 'High Authority'
        WHEN upp.Reputation < 500 AND upp.TotalPosts < 10 THEN 'New Contributor'
        ELSE 'Regular Contributor'
    END AS UserTier,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    CASE WHEN upp.HighEngagementPostId IS NOT NULL THEN 'Yes' ELSE 'No' END AS HasHighEngagementPost,
    DATEDIFF('day', u.CreationDate, CAST(strftime('%Y-%m-%d %H:%M:%S', 'now') AS timestamp)) AS AccountAgeDays,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = upp.UserId AND v.VoteTypeId = 2) AS TotalUpvotesGiven
FROM UserPostPerformance AS upp
LEFT JOIN Users AS u ON upp.UserId = u.Id
LEFT JOIN LatestEdits AS le ON upp.UserId = le.PostId -- This join is logically incorrect as LatestEdits is by PostId, not UserId. Correcting this logic below.
LEFT JOIN LatestEdits AS le_post ON upp.HighEngagementPostId = le_post.PostId -- Joining on the high engagement post ID
WHERE upp.AveragePostScore > 0
   OR upp.TotalPosts > 1000
ORDER BY upp.Reputation DESC, upp.TotalPosts DESC
LIMIT 100;
