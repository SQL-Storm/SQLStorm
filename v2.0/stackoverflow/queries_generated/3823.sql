-- {"query": "3823.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1932} 

-- Benchmark query exercising joins, CTEs, window functions, correlated subqueries,
-- set operators, string handling and NULL logic on the StackOverflow schema.

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(b.GoldCnt,0)   AS GoldBadges,
           COALESCE(b.SilverCnt,0) AS SilverBadges,
           COALESCE(b.BronzeCnt,0) AS BronzeBadges,
           /* correlated subqueries for post counts */
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven
    FROM Users u
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
),

TagInfo AS (
    SELECT t.TagName,
           t.Count                           AS TagUsage,
           COALESCE(e.Title,'')              AS ExcerptTitle,
           COALESCE(w.Title,'')              AS WikiTitle,
           ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

RecentActivity AS (
    SELECT p.OwnerUserId                             AS UserId,
           MAX(p.CreationDate)                       AS LastPostDate,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1)  AS RecentQuestions,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2)  AS RecentAnswers
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
    GROUP BY p.OwnerUserId
),

TopUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           us.QuestionCount,
           us.AnswerCount,
           COALESCE(ra.LastPostDate, TIMESTAMP '1970-01-01') AS LastPostDate,
           ROW_NUMBER() OVER (
               ORDER BY (us.Reputation
                         + us.GoldBadges   * 1000
                         + us.SilverBadges * 500
                         + us.BronzeBadges * 100) DESC
           ) AS Rank
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
    WHERE (us.QuestionCount + us.AnswerCount) > 0
)

SELECT tu.Rank,
       tu.DisplayName,
       tu.Reputation,
       tu.GoldBadges,
       tu.SilverBadges,
       tu.BronzeBadges,
       tu.QuestionCount,
       tu.AnswerCount,
       tu.LastPostDate,
       COALESCE(ti.TagName,'N/A')        AS TopTag,
       ti.TagUsage
FROM TopUsers tu
LEFT JOIN LATERAL (
    SELECT ti.TagName, ti.TagUsage
    FROM TagInfo ti
    WHERE ti.rn = 1
    ORDER BY ti.TagUsage DESC
    LIMIT 1
) ti ON TRUE
WHERE tu.Rank <= 50

UNION ALL

/* a simple summary row using a set operator */
SELECT NULL AS Rank,
       '--- Summary ---' AS DisplayName,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL

UNION ALL

SELECT NULL,
       'Total Users',
       (SELECT COUNT(*) FROM Users),
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL

ORDER BY Rank NULLS LAST, DisplayName;
