-- {"query": "4265.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 995}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS CommentCountCorrelated,
        p.Tags
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
HighScoreQuestions AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        ViewCount,
        FavoriteCount,
        CreationDate,
        ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC) AS QuestionRank
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 100 AND ViewCount > 5000 AND ClosedDate IS NULL
),
UserActivity AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS PostCount,
        SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePostCount,
        AVG(CAST(Score AS NUMERIC(10, 2))) AS AverageScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS NumberOfQuestions,
        SUM(p.Score) AS TotalScoreForTag,
        MAX(p.CreationDate) AS LatestQuestionDate
    FROM Tags AS t
    JOIN Posts AS p ON p.PostTypeId = 1
        AND (',' || COALESCE(p.Tags, '') || ',') LIKE ('%,' || t.TagName || ',%')
    GROUP BY t.TagName, t.Count
    HAVING COUNT(p.Id) > 50
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCountCorrelated AS CommentCountActual,
    hs.Title AS QuestionTitle,
    hs.QuestionRank,
    ua.PostCount AS UserTotalPosts,
    ua.AverageScore AS UserAverageScore,
    tp.TagName,
    tp.TagCount AS GlobalTagCount,
    tp.NumberOfQuestions AS TagQuestionCount,
    tp.TotalScoreForTag AS TagTotalScore,
    CASE
        WHEN rp.Score > 50 AND rp.FavoriteCount > 10 THEN 'Highly Favored'
        WHEN rp.Score < 0 AND rp.AnswerCount = 0 THEN 'Needs Attention'
        WHEN rp.PostTypeName = 'Answer' AND rp.Score >= rp.CommentCountCorrelated THEN 'Well-Received Answer'
        WHEN rp.PostTypeName = 'Question' AND rp.CommentCountCorrelated > rp.AnswerCount THEN 'High Comment Ratio'
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Standard'
    END AS PostStatusCategory,
    CASE WHEN rp.OwnerDisplayName IS NULL OR rp.OwnerDisplayName = '' THEN 'Anonymous' ELSE rp.OwnerDisplayName END AS SafeOwnerName,
    COALESCE(rp.ViewCount, 0) + COALESCE(rp.FavoriteCount, 0) AS EngagementMetric
FROM RankedPosts AS rp
LEFT JOIN HighScoreQuestions AS hs ON rp.PostId = hs.Id
LEFT JOIN UserActivity AS ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN TagPopularity AS tp ON rp.PostTypeId = 1
    AND (',' || COALESCE(rp.Tags, '') || ',') LIKE ('%,' || tp.TagName || ',%')
WHERE rp.rn <= 100
ORDER BY rp.PostCreationDate DESC, rp.Score DESC;