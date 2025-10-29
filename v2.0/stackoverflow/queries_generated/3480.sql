-- {"query": "3480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2222} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE 
                WHEN v.VoteTypeId = 2 THEN 1          -- UpMod
                WHEN v.VoteTypeId = 3 THEN -1         -- DownMod
                ELSE 0
            END) AS VoteScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),

RecentActivity AS (
    SELECT 
        u.Id,
        MAX(ph.CreationDate) AS LastHistoryDate,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13)) AS CloseReopenCount
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),

RankedUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.VoteScore,
        bs.GoldBadgeCount,
        bs.SilverBadgeCount,
        bs.BronzeBadgeCount,
        bs.GoldBadgeNames,
        ra.LastHistoryDate,
        ra.CloseReopenCount,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, bs.GoldBadgeCount DESC) AS RepRank,
        RANK() OVER (
            PARTITION BY CASE WHEN us.Location = 'Unknown' THEN 0 ELSE 1 END
            ORDER BY us.AnswerCount DESC
        ) AS AnswerRankByLocation
    FROM UserStats us
    LEFT JOIN BadgeStats   bs ON bs.UserId = us.Id
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
    WHERE us.Reputation > 1000
)

SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.VoteScore,
    ru.GoldBadgeCount,
    ru.SilverBadgeCount,
    ru.BronzeBadgeCount,
    ru.GoldBadgeNames,
    COALESCE(TO_CHAR(ru.LastHistoryDate, 'YYYY-MM-DD'), 'N/A') AS LastHistory,
    ru.CloseReopenCount,
    ru.RepRank,
    ru.AnswerRankByLocation,
    (SELECT COUNT(*)
       FROM Posts p2
      WHERE p2.OwnerUserId = ru.Id
        AND p2.PostTypeId = 2
        AND p2.Score > 0) AS PositiveAnswerCount,
    CASE
        WHEN ru.GoldBadgeCount >= 5 AND ru.AnswerCount > 0 THEN 'PowerUser'
        WHEN ru.QuestionCount = 0 AND ru.AnswerCount = 0 THEN 'Lurker'
        ELSE 'Contributor'
    END AS UserSegment
FROM RankedUsers ru
WHERE ru.AnswerRankByLocation <= 10

UNION ALL

SELECT
    NULL AS Id,
    '--- Summary ---' AS DisplayName,
    NULL AS Reputation,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount) AS AnswerCount,
    SUM(VoteScore) AS VoteScore,
    SUM(GoldBadgeCount) AS GoldBadgeCount,
    SUM(SilverBadgeCount) AS SilverBadgeCount,
    SUM(BronzeBadgeCount) AS BronzeBadgeCount,
    NULL AS GoldBadgeNames,
    NULL AS LastHistory,
    NULL AS CloseReopenCount,
    NULL AS RepRank,
    NULL AS AnswerRankByLocation,
    NULL AS PositiveAnswerCount,
    NULL AS UserSegment
FROM RankedUsers;
