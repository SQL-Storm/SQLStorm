-- {"query": "39098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2676} 

WITH
-- 1. identify the top‐5 most active tags in the last 30 days by question count
RecentTags AS (
    SELECT
        unnest(string_to_array(substring(p."Tags", 2, length(p."Tags") - 2), '><')) AS TagName,
        p."Id" AS QuestionId
    FROM Posts p
    WHERE p."PostTypeId" = 1
      AND p."CreationDate" >= now() - INTERVAL '30 days'
),
TagQuestionCounts AS (
    SELECT
        rt.TagName,
        COUNT(*) AS QuestionCount
    FROM RecentTags rt
    GROUP BY rt.TagName
),
TopTags AS (
    SELECT TagName
    FROM TagQuestionCounts
    ORDER BY QuestionCount DESC
    LIMIT 5
),

-- 2. aggregate per‐tag metrics: question counts, answer stats, views, comments, edits
TagMetrics AS (
    SELECT
        tt.TagName,
        COUNT(q."Id")                                          AS TotalQuestions,
        AVG(a."Score") FILTER (WHERE a."PostTypeId" = 2)        AS AvgAnswerScore,
        SUM(CASE WHEN a."Id" IS NULL THEN 1 ELSE 0 END)         AS UnansweredCount,
        MAX(q."ViewCount")                                     AS MaxViews,
        AVG(c.cnt)                                             AS AvgCommentsPerQuestion,
        AVG(phc.edits)                                        AS AvgEditsPerQuestion
    FROM Posts q
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(q."Tags", 2, length(q."Tags") - 2), '><')) AS TagName
    ) AS tagExplode ON TRUE
    JOIN TopTags tt ON tt.TagName = tagExplode.TagName
    LEFT JOIN Posts a
      ON a."ParentId" = q."Id"
     AND a."PostTypeId" = 2
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM Comments c
        WHERE c."PostId" = q."Id"
    ) AS c ON TRUE
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS edits
        FROM PostHistory ph
        WHERE ph."PostId" = q."Id"
          AND ph."PostHistoryTypeId" IN (5, 6)
    ) AS phc ON TRUE
    WHERE q."PostTypeId" = 1
      AND q."CreationDate" >= now() - INTERVAL '30 days'
    GROUP BY tt.TagName
),

-- 3. find the top‐3 answerers per tag in that period
TopAnswerers AS (
    SELECT
        tagExplode.TagName,
        a."OwnerUserId",
        COUNT(*) AS AnswerCount,
        RANK() OVER (PARTITION BY tagExplode.TagName ORDER BY COUNT(*) DESC) AS rk
    FROM Posts q
    JOIN Posts a
      ON a."ParentId" = q."Id"
     AND a."OwnerUserId" > 0
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(q."Tags", 2, length(q."Tags") - 2), '><')) AS TagName
    ) AS tagExplode ON TRUE
    WHERE q."PostTypeId" = 1
      AND q."CreationDate" >= now() - INTERVAL '30 days'
    GROUP BY tagExplode.TagName, a."OwnerUserId"
),

-- 4. assemble final JSON aggregates per tag
FinalReport AS (
    SELECT
        tm.TagName,
        tm.TotalQuestions,
        tm.AvgAnswerScore,
        tm.UnansweredCount,
        tm.MaxViews,
        tm.AvgCommentsPerQuestion,
        tm.AvgEditsPerQuestion,
        json_agg(
          json_build_object(
            'UserId', u."Id",
            'DisplayName', u."DisplayName",
            'Answers', ta.AnswerCount,
            'Reputation', u."Reputation"
          )
          ORDER BY ta.AnswerCount DESC
        ) FILTER (WHERE ta.rk <= 3) AS TopAnswerers,
        json_agg(
          json_build_object(
            'BadgeName', b."Name",
            'Class', b."Class",
            'AwardedOn', b."Date"
          )
        ) FILTER (WHERE b."Date" >= now() - INTERVAL '6 months') AS RecentBadges
    FROM TagMetrics tm
    LEFT JOIN TopAnswerers ta
      ON ta.TagName = tm.TagName
     AND ta.rk <= 3
    LEFT JOIN Users u
      ON u."Id" = ta."OwnerUserId"
    LEFT JOIN Badges b
      ON b."UserId" = u."Id"
    GROUP BY
        tm.TagName,
        tm.TotalQuestions,
        tm.AvgAnswerScore,
        tm.UnansweredCount,
        tm.MaxViews,
        tm.AvgCommentsPerQuestion,
        tm.AvgEditsPerQuestion
)

-- final output
SELECT *
FROM FinalReport
ORDER BY TotalQuestions DESC;
