-- {"query": "3924.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2399} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1)                  AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2)                  AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3)                  AS BronzeBadges,
        COALESCE(SUM(p.Score),0)                                         AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                     AS AvgQuestionScore,
        COUNT(p.Id)   FILTER (WHERE p.PostTypeId = 1)                     AS QuestionCount,
        COUNT(p.Id)   FILTER (WHERE p.PostTypeId = 2)                     AS AnswerCount,
        MAX(p.LastActivityDate)                                          AS LastActivity,
        MAX(v.CreationDate)                                              AS LastVoteDate
    FROM Users u
    LEFT JOIN Badges   b ON b.UserId   = u.Id
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes    v ON v.UserId   = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
MedianScore AS (
    SELECT
        percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagUsage AS (
    SELECT
        t.TagName,
        t.Count                     AS TagCount,
        COALESCE(e.Title, w.Title)  AS TagTitle,
        CASE
            WHEN t.IsModeratorOnly = 1 THEN 'ModOnly'
            WHEN t.IsRequired       = 1 THEN 'Required'
            ELSE                           'Normal'
        END                         AS TagCategory
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),
RecentClosedQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        ph.Comment                                    AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ClosedDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
      AND ph.PostHistoryTypeId = 10
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalPostScore,
    us.AvgQuestionScore,
    us.QuestionCount,
    us.AnswerCount,
    us.LastActivity,
    ms.MedianScore,
    CASE
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Pro'
        WHEN us.Reputation BETWEEN 1000  AND 9999  THEN 'Intermediate'
        ELSE 'Newbie'
    END                                          AS ReputationBand,
    COALESCE(rcq.Title, 'NoRecentClosed')       AS RecentClosedTitle,
    COALESCE(rcq.CloseReason, 'N/A')            AS CloseReason,
    STRING_AGG(DISTINCT tu.TagName, ', ') FILTER (WHERE tu.TagCategory = 'Normal') AS PopularTags,
    COUNT(DISTINCT tu.TagName) FILTER (WHERE tu.TagCategory = 'ModOnly')          AS ModOnlyTagCount
FROM UserStats us
CROSS JOIN MedianScore ms
LEFT JOIN RecentClosedQuestions rcq
       ON rcq.rn = 1 AND rcq.OwnerUserId = us.Id
LEFT JOIN TagUsage tu
       ON POSITION('<' || tu.TagName || '>' IN COALESCE(us.DisplayName, '')) > 0
GROUP BY
    us.Id, us.DisplayName, us.Reputation, us.GoldBadges, us.SilverBadges,
    us.BronzeBadges, us.TotalPostScore, us.AvgQuestionScore,
    us.QuestionCount, us.AnswerCount, us.LastActivity,
    ms.MedianScore, rcq.Title, rcq.CloseReason
HAVING COUNT(DISTINCT tu.TagName) > 0

UNION ALL

SELECT
    NULL          AS Id,
    'OverallStats' AS DisplayName,
    NULL          AS Reputation,
    NULL          AS GoldBadges,
    NULL          AS SilverBadges,
    NULL          AS BronzeBadges,
    SUM(us.TotalPostScore)                     AS TotalPostScore,
    AVG(us.AvgQuestionScore)                   AS AvgQuestionScore,
    SUM(us.QuestionCount)                      AS QuestionCount,
    SUM(us.AnswerCount)                        AS AnswerCount,
    MAX(us.LastActivity)                       AS LastActivity,
    ms.MedianScore,
    NULL                                        AS ReputationBand,
    NULL                                        AS RecentClosedTitle,
    NULL                                        AS CloseReason,
    NULL                                        AS PopularTags,
    NULL                                        AS ModOnlyTagCount
FROM UserStats us
CROSS JOIN MedianScore ms
WHERE us.Reputation IS NOT NULL;
