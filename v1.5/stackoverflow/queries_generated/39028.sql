-- {"query": "39028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1853} 

WITH QuestionTags AS (
    SELECT
        p.Id                           AS QuestionId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        p.Score,
        p.ViewCount,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags     IS NOT NULL
),
UserStats AS (
    SELECT
        u.Id                          AS UserId,
        u.DisplayName,
        COUNT(*)                      AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        AVG(p.Score)                  AS AvgPostScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
BadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopActiveUsers AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.TotalPosts
      + COALESCE(bs.GoldBadges,0) * 3
      + COALESCE(bs.SilverBadges,0) * 2
      + COALESCE(bs.BronzeBadges,0) * 1 AS ActivityScore
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON bs.UserId = us.UserId
    ORDER BY ActivityScore DESC
    LIMIT 10
),
TagTrends AS (
    SELECT
        qt.TagName,
        COUNT(*)                    AS Occurrences,
        AVG(qt.Score)               AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qt.ViewCount) AS MedianViews
    FROM QuestionTags qt
    WHERE qt.CreationDate >= now() - interval '1 year'
    GROUP BY qt.TagName
    HAVING COUNT(*) > 100
    ORDER BY Occurrences DESC
    LIMIT 5
)
SELECT
    tau.UserId,
    tau.DisplayName,
    tau.ActivityScore,
    tt.TagName,
    tt.Occurrences,
    tt.AvgScore,
    tt.MedianViews
FROM TopActiveUsers tau
CROSS JOIN TagTrends tt
ORDER BY tau.ActivityScore DESC, tt.Occurrences DESC;
