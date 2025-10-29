-- {"query": "3064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2420} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown')                         AS Location,
        COUNT(DISTINCT b.Id)                                    AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)            AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)            AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)            AS BronzeBadges,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1)    AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2)    AS AnswerCount,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate)                                    AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
RecentActivity AS (
    SELECT
        v.UserId,
        COUNT(*)                         AS VoteCount,
        MAX(v.CreationDate)              AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY v.UserId
),
TopTags AS (
    SELECT
        ut.UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY ut.TagUseCount DESC) AS rn
    FROM (
        SELECT
            p.OwnerUserId                                          AS UserId,
            UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS TagName,
            COUNT(*)                                               AS TagUseCount
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId, TagName
    ) ut
    JOIN Tags t ON t.TagName = ut.TagName
)
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    us.BadgeCount,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(us.AvgPostScore,2)                                   AS AvgPostScore,
    COALESCE(ra.VoteCount,0)                                    AS RecentVoteCount,
    CASE
        WHEN u.Reputation > 20000 THEN 'Legendary'
        WHEN u.Reputation > 10000 THEN 'Guru'
        WHEN u.Reputation > 5000  THEN 'Expert'
        ELSE 'Member'
    END                                                       AS ReputationTier,
    COALESCE(ra.LastVoteDate, us.LastPostDate)                 AS LastActiveDate,
    STRING_AGG(tt.TagName, ', ') FILTER (WHERE tt.rn <= 3)    AS TopThreeTags,
    CASE
        WHEN us.AnswerCount = 0 THEN NULL
        ELSE ROUND(us.AnswerCount::numeric / NULLIF(us.QuestionCount,0), 3)
    END                                                       AS AnswerToQuestionRatio,
    (SELECT p.Title
       FROM Posts p
      WHERE p.OwnerUserId = u.Id
        AND p.PostTypeId = 1
      ORDER BY p.CreationDate DESC
      LIMIT 1)                                                AS MostRecentQuestionTitle
FROM Users u
LEFT JOIN UserStats     us ON us.Id = u.Id
LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
LEFT JOIN TopTags        tt ON tt.UserId = u.Id
WHERE (us.QuestionCount IS NOT NULL AND us.QuestionCount > 5)
   OR (us.AnswerCount   IS NOT NULL AND us.AnswerCount   > 10)
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.Location,
    us.BadgeCount, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.QuestionCount, us.AnswerCount, us.AvgPostScore,
    ra.VoteCount, ra.LastVoteDate, us.LastPostDate,
    tt.rn, tt.TagName
HAVING COUNT(*) FILTER (WHERE tt.rn = 1) > 0
ORDER BY us.Reputation DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL                               AS Id,
    'Aggregated Summary'               AS DisplayName,
    NULL                               AS Reputation,
    NULL                               AS Location,
    SUM(us.BadgeCount)                 AS BadgeCount,
    SUM(us.GoldBadges)                 AS GoldBadges,
    SUM(us.SilverBadges)               AS SilverBadges,
    SUM(us.BronzeBadges)               AS BronzeBadges,
    SUM(us.QuestionCount)              AS QuestionCount,
    SUM(us.AnswerCount)                AS AnswerCount,
    ROUND(AVG(us.AvgPostScore),2)      AS AvgPostScore,
    SUM(COALESCE(ra.VoteCount,0))      AS RecentVoteCount,
    NULL                               AS ReputationTier,
    MAX(COALESCE(ra.LastVoteDate, us.LastPostDate)) AS LastActiveDate,
    NULL                               AS TopThreeTags,
    NULL                               AS AnswerToQuestionRatio,
    NULL                               AS MostRecentQuestionTitle
FROM UserStats us
LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
WHERE us.Reputation IS NOT NULL;
