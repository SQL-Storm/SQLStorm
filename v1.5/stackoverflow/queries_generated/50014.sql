-- {"query": "50014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 830} 

WITH UserActivitySummary AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswerScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AverageAnswerScore,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalFavoriteCount,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RankedAnswers AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        q.ViewCount AS QuestionViewCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as rn
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 -- Answers
),
TopUserTags AS (
    SELECT
        OwnerUserId,
        (array_agg(Tag ORDER BY TagCount DESC))[1] AS PrimaryTag
    FROM (
        SELECT
            OwnerUserId,
            Tag,
            COUNT(*) AS TagCount
        FROM (
            SELECT
                p.OwnerUserId,
                unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
            FROM Posts p
            WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
        ) AS UnnestedTags
        GROUP BY OwnerUserId, Tag
    ) AS TagCounts
    GROUP BY OwnerUserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC, uas.TotalAnswerScore DESC) AS OverallRank,
    uas.QuestionCount,
    uas.AnswerCount,
    CAST(uas.AverageAnswerScore AS DECIMAL(18, 2)) AS AverageAnswerScore,
    uas.TotalFavoriteCount,
    tut.PrimaryTag,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentsMade,
    ra.Score AS TopAnswerScore,
    ra.QuestionViewCount AS TopAnswerQuestionViews,
    EXTRACT(EPOCH FROM (uas.LastPostActivity - u.CreationDate)) / 86400.0 AS ActiveDays
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.OwnerUserId
LEFT JOIN TopUserTags tut ON u.Id = tut.OwnerUserId
LEFT JOIN RankedAnswers ra ON u.Id = ra.OwnerUserId AND ra.rn = 1
WHERE
    u.Reputation > 10000
    AND uas.AnswerCount > uas.QuestionCount
    AND uas.AnswerCount > 50
    AND u.LastAccessDate > (NOW() - INTERVAL '1 year')
    AND (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) > 10
ORDER BY
    OverallRank, u.DisplayName
LIMIT 200;
