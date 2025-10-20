-- {"query": "25017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1789} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0)                             AS TotalPostScore,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)           AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)           AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)       AS RepRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                            AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)        AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)        AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)        AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ',')                    AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
RecentActivity AS (
    SELECT 
        u.Id                                               AS UserId,
        MAX(p.LastActivityDate)                            AS LastPostActivity,
        MAX(v.CreationDate)                                AS LastVote,
        MAX(c.CreationDate)                                AS LastComment
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes    v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.TotalPostScore,
    us.QuestionCount,
    us.AnswerCount,
    us.RepRank,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.BadgeNames,
    ra.LastPostActivity,
    ra.LastVote,
    ra.LastComment,
    COALESCE(NULLIF(ra.LastPostActivity, ra.LastVote), ra.LastVote) AS MostRecentActivity,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation > 10000 THEN 'Pro'
        WHEN us.Reputation > 5000  THEN 'Experienced'
        ELSE 'Novice'
    END                                                      AS ReputationTier,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = us.Id 
       AND p2.Tags IS NOT NULL 
       AND p2.Tags <> '' 
       AND p2.Tags LIKE '%<c#>%')                         AS CSharpTagQuestionCount
FROM UserStats us
LEFT JOIN BadgeStats    bs ON bs.UserId = us.Id
LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
WHERE us.RepRank <= 1000
  AND us.TotalPostScore IS NOT NULL
  AND us.TotalPostScore <> 0

UNION ALL

SELECT 
    NULL,
    '--- Summary ---',
    NULL,
    SUM(us.TotalPostScore),
    SUM(us.QuestionCount),
    SUM(us.AnswerCount),
    NULL,
    SUM(bs.TotalBadges),
    SUM(bs.GoldBadges),
    SUM(bs.SilverBadges),
    SUM(bs.BronzeBadges),
    NULL,
    MAX(ra.LastPostActivity),
    MAX(ra.LastVote),
    MAX(ra.LastComment),
    NULL,
    NULL,
    NULL
FROM UserStats us
LEFT JOIN BadgeStats    bs ON bs.UserId = us.Id
LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
WHERE us.RepRank <= 1000;