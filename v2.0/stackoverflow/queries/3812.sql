-- {"query": "3812.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1840}
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

BadgeStats AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- Move the set-returning function into a lateral subquery to be compatible with Postgres
TagCoverage AS (
    SELECT 
        a.OwnerUserId AS UserId,
        COUNT(DISTINCT tag_name) AS DistinctTagsAnswered
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId
    CROSS JOIN LATERAL (
        SELECT TRIM(both '<>' FROM x) AS tag_name
        FROM UNNEST(string_to_array(p.Tags, '><')) AS t(x)
    ) tags
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
),

RankedUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(tc.DistinctTagsAnswered, 0) AS DistinctTagsAnswered,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, COALESCE(bs.GoldBadges,0) DESC, us.AnswerCount DESC) AS Rank
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
    LEFT JOIN TagCoverage tc ON tc.UserId = us.Id
)

SELECT 
    r.Rank,
    r.DisplayName,
    r.Reputation,
    r.GoldBadges,
    r.SilverBadges,
    r.BronzeBadges,
    r.DistinctTagsAnswered,
    r.QuestionCount,
    r.AnswerCount,
    ROUND(r.AvgAnswerScore, 2) AS AvgAnswerScore,
    COALESCE(
        (SELECT STRING_AGG(t.TagName, ', ' ORDER BY pt.Id)
         FROM Tags t
         JOIN LATERAL (
               SELECT TRIM(both '<>' FROM x) AS TagName, p.Id
               FROM Posts p
               CROSS JOIN UNNEST(string_to_array(p.Tags, '><')) AS u(x)
               WHERE p.OwnerUserId = r.Id AND p.PostTypeId = 1
         ) pt ON pt.TagName = t.TagName
         LIMIT 5),
        'None') AS TopQuestionTags,
    CASE 
        WHEN r.AnswerCount = 0 THEN NULL
        ELSE (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = r.Id)
    END AS LastVoteDate
FROM RankedUsers r
WHERE r.Rank <= 100

UNION ALL

SELECT 
    0 AS Rank,
    'Community' AS DisplayName,
    NULL AS Reputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS DistinctTagsAnswered,
    0 AS QuestionCount,
    0 AS AnswerCount,
    NULL AS AvgAnswerScore,
    NULL AS TopQuestionTags,
    NULL AS LastVoteDate

ORDER BY Rank ASC
LIMIT 101;