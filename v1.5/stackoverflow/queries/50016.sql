-- {"query": "50016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 999} 
WITH PopularTags AS (
    SELECT
        t.TagName,
        t.Id
    FROM Tags t
    WHERE t.Count > 1500 AND t.IsRequired = 'false'
),
UserActivity AS (
    SELECT
        p.OwnerUserId,
        pt.TagName,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Id AS PostId
    FROM Posts p
    JOIN PopularTags pt ON p.Tags LIKE '%<' || pt.TagName || '>%'
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
AggregatedStats AS (
    SELECT
        ua.OwnerUserId,
        ua.TagName,
        SUM(CASE WHEN ua.PostTypeId = 2 THEN ua.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(CASE WHEN ua.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        COUNT(CASE WHEN ua.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        SUM(ua.ViewCount) AS TotalViewCount,
        AVG(CASE WHEN ua.PostTypeId = 2 THEN ua.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(CASE WHEN ua.PostTypeId = 1 THEN ua.CreationDate ELSE NULL END) AS LastQuestionDate
    FROM UserActivity ua
    GROUP BY ua.OwnerUserId, ua.TagName
    HAVING COUNT(CASE WHEN ua.PostTypeId = 2 THEN 1 END) > 5
),
BadgeScores AS (
    SELECT
        b.UserId,
        b.Name AS TagName,
        SUM(
            CASE
                WHEN b.Class = 1 THEN 15 -- Gold
                WHEN b.Class = 2 THEN 5  -- Silver
                WHEN b.Class = 3 THEN 1  -- Bronze
            END
        ) AS BadgeScore
    FROM Badges b
    WHERE b.TagBased = 'true'
    GROUP BY b.UserId, b.Name
),
RankedUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ags.TagName,
        ags.TotalAnswerScore,
        ags.AnswerCount,
        ags.QuestionCount,
        ags.TotalViewCount,
        COALESCE(bs.BadgeScore, 0) AS BadgeScore,
        (ags.TotalAnswerScore * 1.2 + ags.AnswerCount * 2 + COALESCE(bs.BadgeScore, 0) * 10 - ags.QuestionCount * 0.5) AS ExpertiseScore,
        DENSE_RANK() OVER (PARTITION BY ags.TagName ORDER BY (ags.TotalAnswerScore * 1.2 + ags.AnswerCount * 2 + COALESCE(bs.BadgeScore, 0) * 10 - ags.QuestionCount * 0.5) DESC) AS RankInTag
    FROM AggregatedStats ags
    JOIN Users u ON ags.OwnerUserId = u.Id
    LEFT JOIN BadgeScores bs ON ags.OwnerUserId = bs.UserId AND ags.TagName = bs.TagName
    WHERE u.Reputation > 1000
)
SELECT
    ru.TagName,
    ru.RankInTag,
    ru.DisplayName,
    ru.Reputation,
    CAST(ru.ExpertiseScore AS INT) AS ExpertiseScore,
    ru.TotalAnswerScore,
    ru.AnswerCount,
    ru.QuestionCount,
    ru.BadgeScore,
    (SELECT STRING_AGG(c.Text, ' | ') FROM (SELECT c.Text FROM Comments c WHERE c.PostId = p_best.Id ORDER BY c.Score DESC LIMIT 3) c) AS TopCommentsOnBestAnswer
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = ru.UserId
      AND p.PostTypeId = 2 -- Answer
      AND p.Tags LIKE '%<' || ru.TagName || '>%'
    ORDER BY p.Score DESC, p.CreationDate DESC
    LIMIT 1
) p_best ON true
WHERE ru.RankInTag <= 5
ORDER BY ru.TagName, ru.RankInTag;