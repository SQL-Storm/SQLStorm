-- {"query": "9081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3699} 
WITH
-- Recent questions in the last 30 days, one per user
RecentQ AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        COALESCE(p.ViewCount, 0) AS Views,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),

-- Users who have posted more than 10 answers, with answer score aggregates
TopAnswerers AS (
    SELECT
        u.Id        AS UserId,
        u.DisplayName,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score)    AS TotalAnswerScore,
        AVG(a.Score)    AS AvgAnswerScore
    FROM Posts a
    JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= (
          SELECT MIN(CreationDate)
          FROM Posts
          WHERE PostTypeId = 1
      )
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(a.Id) > 10
),

-- Badge counts in the last year, bucketed by class
BadgeCounts AS (
    SELECT
        UserId,
        COUNT(*)                                        AS BadgesEarned,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END)      AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END)      AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END)      AS BronzeBadges
    FROM Badges
    WHERE Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY UserId
),

-- Combine top answerer stats with badge counts and basic user info
UserOverview AS (
    SELECT
        ta.UserId,
        ta.DisplayName,
        ta.AnswerCount,
        ta.TotalAnswerScore,
        ta.AvgAnswerScore,
        COALESCE(bc.BadgesEarned, 0)  AS BadgesEarned,
        COALESCE(bc.GoldBadges,   0)  AS GoldBadges,
        COALESCE(bc.SilverBadges, 0)  AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0)  AS BronzeBadges,
        u.Reputation,
        COALESCE(bc.BadgesEarned, 0) + ta.AnswerCount AS EngagementScore
    FROM TopAnswerers ta
    LEFT JOIN BadgeCounts bc ON bc.UserId = ta.UserId
    JOIN Users u           ON u.Id      = ta.UserId
),

-- Explode Tags into rows and count questions vs. answers per tag
TagUsage AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS ACount
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY 1
),

-- Partition tags into "popular" vs "other"
PopularTags AS (
    SELECT Tag FROM TagUsage WHERE QCount > 1000
),
OtherTags AS (
    SELECT Tag FROM TagUsage WHERE QCount <= 1000
),
TagComparison AS (
    SELECT Tag FROM PopularTags
    UNION
    SELECT Tag FROM OtherTags
    EXCEPT
    SELECT Tag FROM PopularTags
      INTERSECT
    SELECT Tag FROM OtherTags
)

SELECT
    uo.UserId,
    uo.DisplayName,
    uo.Reputation,
    uo.AnswerCount,
    uo.TotalAnswerScore,
    uo.GoldBadges,
    uo.SilverBadges,
    uo.BronzeBadges,
    uo.EngagementScore,
    ru.Id   AS RecentQuestionId,
    ru.Title AS RecentQuestionTitle,
    tu.Tag,
    tu.QCount,
    tu.ACount,
    tc.Tag  AS ComparedTag,
    ss.MaxPostScore,
    ss.MinPostScore,
    -- Correlated subquery counting recent comments by the user
    (SELECT COUNT(*) FROM Comments c
     WHERE c.UserId = uo.UserId
       AND c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    ) AS RecentCommentCount,
    -- Correlated subquery for questions slower than their answers' avg score
    (SELECT COUNT(*) FROM Posts q
     WHERE q.OwnerUserId = uo.UserId
       AND q.PostTypeId = 1
       AND q.Score > uo.AvgAnswerScore
    ) AS AboveAvgQuestions
FROM UserOverview uo
LEFT JOIN RecentQ ru
    ON ru.OwnerUserId = uo.UserId
   AND ru.rn = 1
CROSS JOIN LATERAL (
    SELECT
        MAX(p.Score) AS MaxPostScore,
        MIN(p.Score) AS MinPostScore
    FROM Posts p
    WHERE p.OwnerUserId = uo.UserId
) AS ss
FULL JOIN TagUsage tu
    ON tu.Tag = (
        SELECT substring(uo.DisplayName FROM '^[A-Za-z]+')
    )
FULL JOIN TagComparison tc
    ON COALESCE(tu.Tag, tc.Tag) = tc.Tag
WHERE EXISTS (
    SELECT 1
    FROM Comments c2
    WHERE c2.UserId = uo.UserId
      AND c2.Score > 0
)
  AND uo.EngagementScore > (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY EngagementScore)
    FROM UserOverview
)
ORDER BY uo.EngagementScore DESC, tu.QCount DESC
LIMIT 100;