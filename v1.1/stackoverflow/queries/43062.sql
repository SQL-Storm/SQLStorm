-- {"query": "43062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 604} 
WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersProvided,
        MAX(Score) AS MaxPostScore,
        AVG(Score) AS AvgPostScore,
        SUM(ViewCount) AS TotalViewCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
BadgeSummary AS (
    SELECT 
        UserId,
        COUNT(DISTINCT CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN Class = 3 THEN Id END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
TopTags AS (
    SELECT 
        TagName,
        COUNT(*) AS TagFrequency,
        AVG(p.Score) AS AvgTagScore
    FROM Tags t
    JOIN Posts p ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')::int[])
    GROUP BY TagName
    ORDER BY TagFrequency DESC
    LIMIT 10
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ua.QuestionsAsked,
    ua.AnswersProvided,
    ua.MaxPostScore,
    ua.AvgPostScore,
    ua.TotalViewCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tt.TagName AS MostUsedTag
FROM Users u
LEFT JOIN UserActivity ua ON u.Id = ua.OwnerUserId
LEFT JOIN BadgeSummary bs ON u.Id = bs.UserId
LEFT JOIN LATERAL (
    SELECT 
        TagName
    FROM TopTags tt
    WHERE EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND tt.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')::varchar[])
    )
    ORDER BY tt.TagFrequency DESC
    LIMIT 1
) tt ON true
WHERE u.Reputation > 1000
ORDER BY ua.TotalViewCount DESC, u.Reputation DESC
LIMIT 100;