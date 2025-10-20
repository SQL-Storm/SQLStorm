WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        u.Reputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY u.Id, u.Reputation
),
TagAnalysis AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionsCount,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.Score) AS MaxScore
    FROM Tags t
    JOIN Posts p ON EXISTS (
        SELECT 1
        FROM (
            -- simplified portable tag matching: split by searching for '<tag>' pattern using standard functions
            SELECT TRIM(BOTH '<>' FROM SUBTAG) AS subtag
            FROM (
                SELECT
                    SUBSTRING(p.Tags FROM start_pos FOR (end_pos - start_pos + 1)) AS SUBTAG
                FROM (
                    -- attempt to find start positions; use a numbers table approach if available.
                    -- As a portable fallback, consider only the first occurrence and the whole string.
                    SELECT 1 AS start_pos
                ) sp
                CROSS JOIN LATERAL (
                    -- use LENGTH as a portable replacement for CHAR_LENGTH; if LENGTH isn't available, most dialects support it
                    SELECT LENGTH(p.Tags) AS end_pos
                ) ep
            ) s_inner
        ) s3
        WHERE s3.subtag = t.TagName
    )
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
)
SELECT
    ua.UserId,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgScore,
    ua.TotalEdits,
    ua.TotalBadges,
    ta.TagName,
    ta.QuestionsCount,
    ta.AvgViewCount,
    ta.MaxScore,
    ua.Reputation,
    ua.ReputationRank
FROM UserActivity ua
JOIN Posts p ON ua.UserId = p.OwnerUserId
JOIN TagAnalysis ta ON p.Tags LIKE '%' || '<' || ta.TagName || '>' || '%'
WHERE ua.ReputationRank <= 100
GROUP BY
    ua.UserId,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgScore,
    ua.TotalEdits,
    ua.TotalBadges,
    ta.TagName,
    ta.QuestionsCount,
    ta.AvgViewCount,
    ta.MaxScore,
    ua.Reputation,
    ua.ReputationRank
ORDER BY ua.TotalPosts DESC, ta.QuestionsCount DESC
LIMIT 20;