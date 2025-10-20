-- {"query": "35094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 774} 
WITH TopActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(COALESCE(p.Score, 0)) AS PostScore,
        SUM(COALESCE(c.Score, 0)) AS CommentScore,
        MAX(u.Reputation) AS MaxReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10 AND COUNT(DISTINCT c.Id) > 20
    ORDER BY PostScore DESC
    LIMIT 100
),
PopularTags AS (
    SELECT
        t.TagName,
        t.Count AS TagCount
    FROM Tags t
    WHERE t.Count > 1000
    ORDER BY t.Count DESC
    LIMIT 50
),
PostsWithPopularTags AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Score,
        p.ViewCount,
        t.TagName
    FROM Posts p
    JOIN PopularTags t
      ON ('<' || t.TagName || '>') = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    WHERE p.PostTypeId = 1
),
HighImpactQuestions AS (
    SELECT
        pwpt.PostId,
        pwpt.OwnerUserId,
        pwpt.Title,
        pwpt.TagName,
        pwpt.Score,
        pwpt.ViewCount,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN a.Score > 5 THEN 1 ELSE 0 END) AS HighScoreAnswers,
        AVG(COALESCE(a.Score,0)) AS AvgAnswerScore
    FROM PostsWithPopularTags pwpt
    LEFT JOIN Posts a ON a.ParentId = pwpt.PostId AND a.PostTypeId = 2
    WHERE pwpt.Score > 10 AND pwpt.ViewCount > 1000
    GROUP BY pwpt.PostId, pwpt.OwnerUserId, pwpt.Title, pwpt.TagName, pwpt.Score, pwpt.ViewCount
    HAVING COUNT(a.Id) > 5
),
HotQuestionsComments AS (
    SELECT
        q.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM HighImpactQuestions q
    LEFT JOIN Comments c ON c.PostId = q.PostId
    GROUP BY q.PostId
)
SELECT 
    q.PostId,
    q.Title,
    q.TagName,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.HighScoreAnswers,
    q.AvgAnswerScore,
    hc.CommentCount,
    hc.AvgCommentScore,
    u.DisplayName AS Author,
    u.MaxReputation,
    u.TotalBadges,
    bt.BadgeNames
FROM HighImpactQuestions q
JOIN HotQuestionsComments hc ON hc.PostId = q.PostId
JOIN TopActiveUsers u ON u.UserId = q.OwnerUserId
LEFT JOIN (
    SELECT 
        b.UserId,
        string_agg(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
) bt ON bt.UserId = u.UserId
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 50;