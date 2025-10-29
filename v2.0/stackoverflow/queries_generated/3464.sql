-- {"query": "3464.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2826} 

WITH
    BadgeAgg AS (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Badges
        GROUP BY UserId
    ),
    PostAgg AS (
        SELECT
            OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE PostTypeId = 1) AS QCnt,
            COUNT(*) FILTER (WHERE PostTypeId = 2) AS ACnt,
            MAX(CreationDate) AS LastPostDt,
            AVG(Score) FILTER (WHERE PostTypeId IN (1,2)) AS AvgScore
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ),
    UserScore AS (
        SELECT
            u.Id,
            COALESCE(u.DisplayName,'[deleted]') AS DisplayName,
            u.Reputation,
            COALESCE(b.GoldCnt,0)   AS GoldBadges,
            COALESCE(b.SilverCnt,0) AS SilverBadges,
            COALESCE(b.BronzeCnt,0) AS BronzeBadges,
            COALESCE(p.QCnt,0)      AS QuestionCount,
            COALESCE(p.ACnt,0)      AS AnswerCount,
            ROUND(COALESCE(p.AvgScore,0),2) AS AvgPostScore,
            p.LastPostDt,
            CONCAT('U',u.Id,'_',REPLACE(COALESCE(u.DisplayName,''), ' ', '_')) AS UserKey
        FROM Users u
        LEFT JOIN BadgeAgg b ON u.Id = b.UserId
        LEFT JOIN PostAgg  p ON u.Id = p.UserId
    ),
    RankedUsers AS (
        SELECT
            *,
            ROW_NUMBER() OVER (ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC) AS rn,
            RANK()   OVER (ORDER BY QuestionCount DESC) AS q_rank
        FROM UserScore
        WHERE Reputation >= 500
    ),
    RecentClose AS (
        SELECT
            ph.PostId,
            ph.CreationDate,
            ph.Comment AS CloseReason
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10   -- Post Closed
    ),
    UserLastClose AS (
        SELECT
            po.OwnerUserId AS UserId,
            rc.CloseReason,
            rc.CreationDate AS CloseDate
        FROM Posts po
        JOIN LATERAL (
            SELECT *
            FROM RecentClose rc
            WHERE rc.PostId = po.Id
            ORDER BY rc.CreationDate DESC
            LIMIT 1
        ) rc ON true
    )
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AvgPostScore,
    ru.LastPostDt,
    COALESCE(ulc.CloseReason,'Never Closed') AS LastCloseReason,
    CASE WHEN ru.AnswerCount = 0 THEN NULL ELSE
        (SELECT TOP 1 p.Title
         FROM Posts p
         WHERE p.OwnerUserId = ru.Id AND p.PostTypeId = 2
         ORDER BY p.Score DESC, p.CreationDate DESC) END AS TopAnswerTitle
FROM RankedUsers ru
LEFT JOIN UserLastClose ulc ON ru.Id = ulc.UserId
WHERE ru.rn <= 100
UNION ALL
SELECT
    u.Id,
    COALESCE(u.DisplayName,'[deleted]') AS DisplayName,
    u.Reputation,
    0,0,0,
    0,0,NULL,NULL,
    'No Activity' AS LastCloseReason,
    NULL AS TopAnswerTitle
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation >= 500
ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC
LIMIT 150;
