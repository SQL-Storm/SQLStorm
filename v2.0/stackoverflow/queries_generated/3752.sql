-- {"query": "3752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2101} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore
    FROM Users u
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT 
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><'))
),
TopTags AS (
    SELECT 
        tu.UserId,
        STRING_AGG(tu.Tag, ', ' ORDER BY tu.TagCount DESC) FILTER (WHERE rn <= 3) AS Top3Tags
    FROM (
        SELECT 
            tu.*,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC) AS rn
        FROM TagUsage tu
    ) tu
    GROUP BY tu.UserId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(COALESCE(us.AvgPostScore,0),2) AS AvgPostScore,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    bc.TotalBadges,
    tt.Top3Tags,
    CASE 
        WHEN us.LastPostDate IS NULL THEN 'Never posted'
        WHEN us.LastPostDate < CURRENT_DATE - INTERVAL '1 year' THEN 'Inactive >1y'
        WHEN us.LastPostDate < CURRENT_DATE - INTERVAL '30 days' THEN 'Inactive >30d'
        ELSE 'Active'
    END AS ActivityStatus,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS ReputationRank
FROM UserStats us
LEFT JOIN BadgeCounts bc ON bc.UserId = us.Id
LEFT JOIN TopTags tt ON tt.UserId = us.Id
WHERE us.Reputation > 1000
  AND (us.QuestionCount + us.AnswerCount) > 0
  AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = us.Id 
          AND p.Title ILIKE '%sql%' 
          AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
      )
UNION ALL
SELECT 
    NULL AS Id,
    'Aggregate' AS DisplayName,
    SUM(us.Reputation) AS Reputation,
    SUM(us.NetVotes) AS NetVotes,
    SUM(us.QuestionCount) AS QuestionCount,
    SUM(us.AnswerCount) AS AnswerCount,
    ROUND(AVG(us.AvgPostScore),2) AS AvgPostScore,
    SUM(COALESCE(bc.GoldBadges,0)) AS GoldBadges,
    SUM(COALESCE(bc.SilverBadges,0)) AS SilverBadges,
    SUM(COALESCE(bc.BronzeBadges,0)) AS BronzeBadges,
    SUM(COALESCE(bc.TotalBadges,0)) AS TotalBadges,
    NULL AS Top3Tags,
    NULL AS ActivityStatus,
    NULL AS ReputationRank
FROM UserStats us
LEFT JOIN BadgeCounts bc ON bc.UserId = us.Id
WHERE us.Reputation > 1000
  AND (us.QuestionCount + us.AnswerCount) > 0
ORDER BY ReputationRank NULLS LAST, Reputation DESC
LIMIT 100;