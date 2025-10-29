-- {"query": "4525.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 938} 
WITH TagCounts AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.AnswerCount) AS AvgAnswers,
        MAX(p.Score) AS MaxScore
    FROM Tags t
    JOIN Posts p ON t.TagName = ANY(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' '))
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-1 year')
    GROUP BY t.TagName
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        CASE WHEN u.LastAccessDate < DATE('now', '-90 days') THEN 'Inactive' ELSE 'Active' END AS UserStatus
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATE('now', '-2 years')
    GROUP BY u.Id, u.DisplayName, u.LastAccessDate
),
PostAggregates AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostTypeName,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) AS DaysSinceLastActivity,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= DATE('now', '-3 months')
)
SELECT
    tc.TagName,
    tc.QuestionCount,
    tc.AvgAnswers,
    tc.MaxScore,
    ua.DisplayName AS TopUser,
    ua.CommentCount,
    ua.UpvoteCount,
    ua.DownvoteCount,
    ua.BadgeCount,
    ua.UserStatus,
    pa.Title AS TopPostTitle,
    pa.PostTypeName AS TopPostType,
    pa.Score AS TopPostScore,
    pa.ViewCount AS TopPostViewCount,
    pa.CommentCount AS TopPostCommentCount,
    pa.FavoriteCount AS TopPostFavoriteCount,
    pa.DaysSinceLastActivity AS TopPostDaysSinceLastActivity,
    pa.ScoreRank AS TopPostScoreRank,
    CASE
        WHEN tc.MaxScore > 100 AND tc.AvgAnswers > 5 THEN 'High Engagement'
        WHEN tc.QuestionCount < 10 THEN 'Niche'
        WHEN ua.BadgeCount >= 5 AND ua.UserStatus = 'Active' THEN 'Influential User'
        ELSE 'Standard'
    END AS Category,
    COALESCE(ua.DisplayName, 'Anonymous') AS DisplayedUser,
    IIF(pa.ScoreRank <= 5, 'Top Ranked', 'Other') AS RankIndicator,
    CAST(RAND() * 1000 AS INTEGER) AS RandomMetric
FROM TagCounts tc
LEFT JOIN UserActivity ua ON tc.TagName = (SELECT TagName FROM Tags WHERE Id = (SELECT MIN(Id) FROM Tags)) -- Arbitrary join condition for demonstration
FULL OUTER JOIN PostAggregates pa ON pa.ScoreRank = 1 -- Example of a potential join that might not yield many results
WHERE tc.QuestionCount > 50
   OR ua.UpvoteCount > 1000
   OR pa.ViewCount > 50000
ORDER BY
    tc.MaxScore DESC NULLS LAST,
    ua.BadgeCount DESC,
    pa.ViewCount DESC;