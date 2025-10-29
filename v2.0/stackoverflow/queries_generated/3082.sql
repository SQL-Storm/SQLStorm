-- {"query": "3082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2364} 

WITH UserStats AS (
    SELECT
        u.Id                                    AS UserId,
        COALESCE(u.DisplayName, 'Anonymous')    AS DisplayName,
        u.Reputation,
        u.CreationDate                          AS UserCreated,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)          AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)          AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)        AS QuestionScoreSum,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)        AS AnswerScoreSum,
        COUNT(b.Id)                                   AS BadgeCount,
        MAX(b.Date)                                   AS LastBadgeDate,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b  ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),

TopTags AS (
    SELECT
        a.OwnerUserId                     AS UserId,
        t.TagName,
        COUNT(*)                          AS AnsweredCount,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts a
    JOIN Posts q
        ON q.Id = a.ParentId
       AND q.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(substr(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
    ) AS taglist
    JOIN Tags t
        ON t.TagName = taglist.TagName
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId, t.TagName
),

RecentActivity AS (
    SELECT
        u.Id                                 AS UserId,
        MAX(p.LastActivityDate)              AS LastPostActivity,
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id) AS LastVoteDate,
        (SELECT MAX(b.Date)         FROM Badges b WHERE b.UserId = u.Id) AS LastBadgeEarned
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),

Combined AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.QuestionScoreSum,
        us.AnswerScoreSum,
        us.BadgeCount,
        us.GoldBadges,
        us.ReputationRank,
        COALESCE(rt.TagName, 'None')               AS TopTag,
        COALESCE(rt.AnsweredCount, 0)              AS TopTagAnswerCount,
        COALESCE(ra.LastPostActivity, us.UserCreated) AS RecentPostActivity,
        COALESCE(ra.LastVoteDate, us.UserCreated)    AS RecentVoteActivity,
        COALESCE(ra.LastBadgeEarned, us.UserCreated) AS RecentBadgeActivity,
        CASE
            WHEN us.Reputation >= 20000 THEN 'Legendary'
            WHEN us.Reputation >= 10000 THEN 'Expert'
            WHEN us.Reputation >= 5000  THEN 'Experienced'
            ELSE 'Newbie'
        END                                         AS ReputationTier,
        CONCAT('U', us.UserId, '-', COALESCE(us.DisplayName, 'Anon')) AS UserKey
    FROM UserStats us
    LEFT JOIN (
        SELECT UserId, TagName, AnsweredCount
        FROM TopTags
        WHERE TagRank = 1
    ) rt ON rt.UserId = us.UserId
    LEFT JOIN RecentActivity ra ON ra.UserId = us.UserId
)

SELECT *
FROM Combined
WHERE (ReputationRank <= 1000 OR BadgeCount > 10)
  AND (TopTag <> 'None' OR QuestionCount > 0)
ORDER BY ReputationRank
LIMIT 500

UNION ALL

SELECT
    NULL                                   AS UserId,
    'Aggregate Summary'                    AS DisplayName,
    NULL                                   AS Reputation,
    SUM(QuestionCount)                     AS QuestionCount,
    SUM(AnswerCount)                       AS AnswerCount,
    SUM(QuestionScoreSum)                  AS QuestionScoreSum,
    SUM(AnswerScoreSum)                    AS AnswerScoreSum,
    SUM(BadgeCount)                        AS BadgeCount,
    NULL                                   AS GoldBadges,
    NULL                                   AS ReputationRank,
    NULL                                   AS TopTag,
    NULL                                   AS TopTagAnswerCount,
    MAX(RecentPostActivity)                AS RecentPostActivity,
    MAX(RecentVoteActivity)                AS RecentVoteActivity,
    MAX(RecentBadgeActivity)               AS RecentBadgeActivity,
    NULL                                   AS ReputationTier,
    'TOTAL'                                AS UserKey
FROM Combined
WHERE ReputationRank IS NOT NULL;
