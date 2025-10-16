-- {"query": "9077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3228} 

WITH
-- 1. Summarize per‐user activity (questions, answers, votes) with a window for reputation rank
UserActivity AS (
    SELECT
        u.Id             AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(
            CASE
               WHEN v.VoteTypeId = 2 THEN  1
               WHEN v.VoteTypeId = 3 THEN -1
               ELSE 0
            END
        ) AS VoteBalance,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId       = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- 2. Pick “top” questions per user with body‐length heuristic + window‐rank
TopQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', ''))) AS CodeSnippets,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerBestRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > (
          SELECT AVG(score)
          FROM Posts
          WHERE PostTypeId = 1
      )
),
-- 3. Aggregate tag‐statistics (question counts & avg score), only for tags with >50 questions
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)     AS QCount,
        AVG(p.Score)    AS AvgScore
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50
),
-- 4. Combine user activity with tag stats into a single metric
Combined AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ts.TagName,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.VoteBalance,
        ts.QCount,
        ts.AvgScore,
        ua.Reputation + ts.QCount * COALESCE(ua.VoteBalance, 0) AS WeightedMetric
    FROM UserActivity ua
    CROSS JOIN TagStats ts
    WHERE ua.RepRank < 100
)
-- 5. Final selection with set operators, correlated subquery, window functions and NULL logic
(
    SELECT
        c.UserId,
        c.DisplayName,
        STRING_AGG(DISTINCT c.TagName, ', ' ORDER BY c.TagName)       AS TagsEngaged,
        SUM(c.WeightedMetric) OVER (PARTITION BY c.UserId)            AS TotalImpact,
        RANK() OVER (ORDER BY SUM(c.WeightedMetric) OVER (PARTITION BY c.UserId) DESC) AS ImpactRank
    FROM Combined c
    WHERE c.WeightedMetric > (
        SELECT AVG(cc.WeightedMetric)
        FROM Combined cc
        WHERE cc.TagName = c.TagName
    )
    GROUP BY c.UserId, c.DisplayName
    HAVING COUNT(*) > 3
)
INTERSECT
(
    SELECT
        u.Id,
        u.DisplayName,
        NULL::varchar             AS TagsEngaged,
        0                         AS TotalImpact,
        NULL::integer             AS ImpactRank
    FROM Users u
    WHERE u.Views > 10000
)
EXCEPT
(
    SELECT
        u.UserId,
        u.DisplayName,
        NULL,
        0,
        NULL
    FROM Combined u
    WHERE u.DisplayName IS NULL
)
ORDER BY ImpactRank;
