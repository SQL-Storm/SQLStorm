-- {"query": "35058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 768} 
WITH MostActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS Answers,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE u.Reputation > 1000 AND p.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
    ORDER BY TotalPosts DESC
    LIMIT 50
),
TopTags AS (
    SELECT 
        pt.Id AS PostId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE pt.Name = 'Question' AND p.CreationDate > NOW() - INTERVAL '2 years'
),
TagStats AS (
    SELECT
        tt.TagName,
        COUNT(*) AS TagUseCount
    FROM TopTags tt
    GROUP BY tt.TagName
    ORDER BY TagUseCount DESC
    LIMIT 20
),
UserTagActivity AS (
    SELECT
        mu.UserId,
        tt.TagName,
        COUNT(*) AS PostsWithThisTag
    FROM MostActiveUsers mu
    JOIN Posts p ON p.OwnerUserId = mu.UserId
    JOIN PostTypes pt ON pt.Id = p.PostTypeId AND pt.Name = 'Question'
    JOIN TopTags tt ON tt.PostId = p.Id
    WHERE tt.TagName IN (SELECT TagName FROM TagStats)
    GROUP BY mu.UserId, tt.TagName
),
UserScoreBreakdown AS (
    SELECT
        mu.UserId,
        SUM(p.Score) AS TotalUserScore,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativePosts,
        AVG(p.Score::float) AS AverageScore
    FROM MostActiveUsers mu
    JOIN Posts p ON p.OwnerUserId = mu.UserId
    GROUP BY mu.UserId
)
SELECT
    mu.UserRank,
    mu.DisplayName,
    mu.Questions,
    mu.Answers,
    usb.TotalUserScore,
    usb.AverageScore,
    usb.PositivePosts,
    usb.NegativePosts,
    ARRAY_AGG(
        JSON_BUILD_OBJECT('tag', uta.TagName, 'count', uta.PostsWithThisTag)
        ORDER BY uta.PostsWithThisTag DESC
    ) FILTER (WHERE uta.TagName IS NOT NULL) AS TopTagActivity,
    COUNT(DISTINCT b.Id) AS BadgesLastYear
FROM MostActiveUsers mu
LEFT JOIN UserScoreBreakdown usb ON usb.UserId = mu.UserId
LEFT JOIN UserTagActivity uta ON uta.UserId = mu.UserId
LEFT JOIN Badges b ON b.UserId = mu.UserId AND b.Date > NOW() - INTERVAL '1 year'
GROUP BY 
    mu.UserRank, mu.DisplayName, mu.Questions, mu.Answers,
    usb.TotalUserScore, usb.AverageScore, usb.PositivePosts, usb.NegativePosts
ORDER BY mu.UserRank
LIMIT 20;