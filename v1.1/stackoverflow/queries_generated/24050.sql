-- {"query": "24050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2393} 

/* Benchmark query – complex mix of CTEs, outer joins, window functions,
   correlated sub‑queries, set operators, string manipulation and NULL logic */

WITH

-- 1️⃣  Split the <tag>…</tag> list from question posts
question_tags AS (
    SELECT
        p.Id        AS PostId,
        t.TagName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    FROM Posts p
    CROSS APPLY (
        SELECT TRIM(BOTH '><' FROM v.tag) AS TagName
        FROM unnest(
                string_to_array(
                    substring(p.Tags, 2, length(p.Tags)-2), '><'
                )
            ) AS v(tag)
    ) t
    WHERE p.PostTypeId = 1
),

-- 2️⃣  Same split for answer posts (for the union‑all set operator)
answer_tags AS (
    SELECT
        p.Id        AS PostId,
        t.TagName
    FROM Posts p
    CROSS APPLY (
        SELECT TRIM(BOTH '><' FROM v.tag) AS TagName
        FROM unnest(
                string_to_array(
                    substring(p.Tags, 2, length(p.Tags)-2), '><'
                )
            ) AS v(tag)
    ) t
    WHERE p.PostTypeId = 2
),

-- 3️⃣  Almost every tag that ever appears – union of questions & answers
all_tags AS (
    SELECT TagName FROM question_tags
    UNION ALL
    SELECT TagName FROM answer_tags
),

-- 4️⃣  Core statistics per tag (questions only)
tag_stats AS (
    SELECT
        qt.TagName,
        COUNT(*)                                   AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN qt.PostId END)
                                                     AS ClosedQuestions,
        AVG(qt.Score)                               AS AvgScore,
        COALESCE(
            MAX(CASE WHEN qt.AcceptedAnswerId IS NOT NULL THEN qt.AcceptedAnswerId END),
            -1
        )                                            AS AnyAcceptedAnswer,
        STRING_AGG(
            CASE WHEN qt.AcceptedAnswerId IS NOT NULL THEN qt.PostId::text END,
            ', '
        ) FILTER (WHERE qt.AcceptedAnswerId IS NOT NULL) AS WithAccepted,
        (SELECT MAX(ph2.CreationDate)          -- ❌  Correlated sub‑query
         FROM PostHistory ph2
         WHERE ph2.PostId = qt.PostId
           AND ph2.PostHistoryTypeId = 5      -- Edit Body
        )                                            AS LastBodyEdit
    FROM question_tags qt
    LEFT JOIN PostHistory ph
        ON ph.PostId = qt.PostId AND ph.PostHistoryTypeId = 10   -- Closed
    GROUP BY qt.TagName
),

-- 5️⃣  Badge counts per tag – correlated logic with NULL handling
tag_badge_counts AS (
    SELECT
        t.TagName,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0)  AS Gold,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0)  AS Silver
    FROM Tags t
    LEFT JOIN Badges b ON b.UserId = t.Id   -- ← NULL logic: user may have no badges
    GROUP BY t.TagName
),

-- 6️⃣  Rank views per tag (window function)
tag_view_rank AS (
    SELECT
        qt.TagName,
        qt.PostId,
        qt.ViewCount,
        RANK() OVER (PARTITION BY qt.TagName ORDER BY qt.ViewCount DESC) AS Rank
    FROM question_tags qt
),

-- 7️⃣  Final cross‑join with outer joins
final_cross AS (
    SELECT
        ts.TagName,
        ts.TotalQuestions,
        ts.ClosedQuestions,
        ts.AvgScore,
        ts.WithAccepted,
        CASE WHEN ts.WithAccepted IS NOT NULL THEN 'Yes' ELSE 'No' END AS HasAccepted,
        tb.Gold,
        tb.Silver,
        vr.PostId   AS TopViewPostId,
        vr.ViewCount AS TopViewScore,
        ts.LastBodyEdit
    FROM tag_stats ts
    LEFT JOIN tag_badge_counts tb ON tb.TagName = ts.TagName
    LEFT JOIN tag_view_rank vr
        ON vr.TagName = ts.TagName AND vr.Rank = 1
)

-- 8️⃣  Final output – apply set operator to merge with tags that have no questions
SELECT
    fc.TagName,
    COALESCE(fc.TotalQuestions, 0)          AS TotalQuestions,
    COALESCE(fc.ClosedQuestions, 0)         AS ClosedQuestions,
    COALESCE(fc.AvgScore, 0)                AS AvgScore,
    fc.HasAccepted,
    COALESCE(fc.Gold, 0)                    AS GoldBadges,
    COALESCE(fc.Silver, 0)                  AS SilverBadges,
    fc.TopViewPostId,
    fc.TopViewScore,
    fc.LastBodyEdit
FROM final_cross fc
UNION ALL
SELECT
    at.TagName,
    0 AS TotalQuestions,
    0 AS ClosedQuestions,
    0 AS AvgScore,
    'No' AS HasAccepted,
    0 AS GoldBadges,
    0 AS SilverBadges,
    NULL AS TopViewPostId,
    NULL AS TopViewScore,
    NULL AS LastBodyEdit
FROM all_tags at
LEFT JOIN final_cross fc ON fc.TagName = at.TagName
WHERE fc.TagName IS NULL
ORDER BY TotalQuestions DESC NULLS LAST, TagName;
