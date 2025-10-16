-- {"query": "13095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 710} 

WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersProvided,
        MAX(CreationDate) AS LastActivity,
        AVG(Score) AS AvgScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.QuestionsAsked,
        ua.AnswersProvided,
        ua.AvgScore,
        DENSE_RANK() OVER (ORDER BY ua.AvgScore DESC NULLS LAST) AS AvgScoreRank
    FROM Users u
    LEFT JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    WHERE u.Views > 1000
),
EditedPosts AS (
    SELECT 
        ph.PostId,
        STRING_AGG(DISTINCT COALESCE(u.DisplayName, 'Community'), ', ') AS Editors,
        COUNT(ph.Id) AS EditCount
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
),
PostMetrics AS (
    SELECT 
        p.Id,
        p.Title,
        ep.Editors,
        ep.EditCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes
    FROM Posts p
    LEFT JOIN EditedPosts ep ON p.Id = ep.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, ep.Editors, ep.EditCount, p.OwnerUserId
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.QuestionsAsked,
    tc.AnswersProvided,
    ROUND(tc.AvgScore, 2) AS AvgScore,
    pm.Title,
    pm.Editors,
    pm.EditCount,
    pm.Upvotes,
    pm.Downvotes,
    LAG(pm.Upvotes, 1, 0) OVER (PARTITION BY tc.Id ORDER BY pm.Upvotes DESC) AS PrevPostUpvotes
FROM TopContributors tc
INNER JOIN PostMetrics pm ON tc.Id = pm.OwnerUserId
WHERE tc.AvgScoreRank <= 10 AND pm.UserPostRank <= 3
ORDER BY tc.AvgScoreRank, pm.Upvotes DESC;
