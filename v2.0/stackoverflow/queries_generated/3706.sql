-- {"query": "3706.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2345} 

WITH UserStats AS (
    SELECT 
        u.Id                                      AS UserId,
        COALESCE(u.DisplayName, 'Anonymous')      AS DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown')           AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate)                       AS LastPostDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT b.Id)                      AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts       p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes       v ON v.PostId = p.Id
    LEFT JOIN Badges      b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

RecentActivity AS (
    SELECT 
        u.Id                                      AS UserId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastDeleteDate,
        MAX(c.CreationDate)                       AS LastCommentDate
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments    c  ON c.UserId = u.Id
    GROUP BY u.Id
),

RankedUsers AS (
    SELECT 
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.AnswerCount DESC) AS ReputationRank,
        RANK()       OVER (ORDER BY us.QuestionCount DESC)                  AS QuestionRank,
        NTILE(4)    OVER (ORDER BY us.BadgeCount DESC)                     AS BadgeQuartile
    FROM UserStats us
)

SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ROUND(ru.AvgPostScore,2)               AS AvgPostScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ra.LastCloseDate,
    ra.LastDeleteDate,
    ra.LastCommentDate,
    ru.ReputationRank,
    ru.QuestionRank,
    ru.BadgeQuartile,
    CASE
        WHEN ru.BadgeCount = 0               THEN 'No Badges'
        WHEN ru.GoldBadges IS NOT NULL       THEN 'Gold Holder'
        ELSE                                   'Badge Holder'
    END                                    AS BadgeStatus,
    COALESCE(NULLIF(ru.Location, ''), 'N/A') AS UserLocation,
    CONCAT('User_', ru.UserId)             AS UserTag
FROM RankedUsers ru
LEFT JOIN RecentActivity ra ON ra.UserId = ru.UserId
WHERE (ru.ReputationRank <= 1000)
   OR (ru.BadgeCount > 0 AND ru.QuestionCount > 0)
UNION ALL
SELECT
    -1                                    AS UserId,
    'Aggregate'                           AS DisplayName,
    SUM(us.Reputation)                    AS Reputation,
    SUM(us.QuestionCount)                 AS QuestionCount,
    SUM(us.AnswerCount)                   AS AnswerCount,
    ROUND(AVG(us.AvgPostScore),2)         AS AvgPostScore,
    NULL                                  AS GoldBadges,
    NULL                                  AS SilverBadges,
    NULL                                  AS BronzeBadges,
    MAX(ra.LastCloseDate)                 AS LastCloseDate,
    MAX(ra.LastDeleteDate)                AS LastDeleteDate,
    MAX(ra.LastCommentDate)               AS LastCommentDate,
    NULL                                  AS ReputationRank,
    NULL                                  AS QuestionRank,
    NULL                                  AS BadgeQuartile,
    'Summary'                             AS BadgeStatus,
    NULL                                  AS UserLocation,
    'All_Users'                           AS UserTag
FROM UserStats us
LEFT JOIN RecentActivity ra ON ra.UserId = us.UserId
WHERE us.Reputation > 0
HAVING COUNT(*) > 0
ORDER BY ReputationRank;
