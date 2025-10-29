-- {"query": "3348.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2409} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) AS QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS AnswerScore,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesGiven,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViews,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Id IS NOT NULL) AS TopContributors
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
),
RankedUsers AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY (ua.QuestionScore + ua.AnswerScore) DESC) AS OverallRank,
        RANK() OVER (
            PARTITION BY
                CASE
                    WHEN ua.Reputation >= 20000 THEN 'High'
                    WHEN ua.Reputation >= 10000 THEN 'Medium'
                    ELSE 'Low'
                END
            ORDER BY ua.Reputation DESC
        ) AS ReputationTierRank
    FROM UserActivity ua
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.QuestionScore,
    ru.AnswerScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.OverallRank,
    ru.ReputationTierRank,
    COALESCE(ts.TagName, 'NoTag') AS SampleTag,
    ts.TotalPosts,
    ts.TotalScore,
    ts.AvgViews,
    ts.TopContributors
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT
        ts_inner.TagName,
        ts_inner.TotalPosts,
        ts_inner.TotalScore,
        ts_inner.AvgViews,
        ts_inner.TopContributors
    FROM TagStats ts_inner
    WHERE ts_inner.TagName ILIKE ANY (ARRAY[
        (SELECT unnest(string_to_array(ru.DisplayName, ' ')) LIMIT 1),
        (SELECT unnest(string_to_array(ru.DisplayName, ' ')) LIMIT 1 OFFSET 1)
    ])
    ORDER BY ts_inner.TotalPosts DESC
    LIMIT 1
) ts ON TRUE
WHERE ru.OverallRank <= 500

UNION ALL

SELECT
    NULL AS UserId,
    '--- Summary ---' AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS QuestionScore,
    NULL AS AnswerScore,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS OverallRank,
    NULL AS ReputationTierRank,
    NULL AS SampleTag,
    NULL AS TotalPosts,
    NULL AS TotalScore,
    NULL AS AvgViews,
    NULL AS TopContributors
FROM (SELECT 1) dummy
UNION ALL
SELECT
    NULL,
    'Total Users',
    (SELECT COUNT(*) FROM Users),
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
UNION ALL
SELECT
    NULL,
    'Total Questions',
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1),
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
UNION ALL
SELECT
    NULL,
    'Total Answers',
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2),
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
UNION ALL
SELECT
    NULL,
    'Total Gold Badges',
    (SELECT COUNT(*) FROM Badges WHERE Class = 1),
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
ORDER BY OverallRank NULLS LAST, UserId;