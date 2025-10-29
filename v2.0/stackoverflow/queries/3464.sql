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
            COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QCnt,
            COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS ACnt,
            MAX(CreationDate) AS LastPostDt,
            AVG(CASE WHEN PostTypeId IN (1,2) THEN Score END) AS AvgScore
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
            ('U' || u.Id || '_' || REPLACE(COALESCE(u.DisplayName,''), ' ', '_')) AS UserKey
        FROM Users u
        LEFT JOIN BadgeAgg b ON u.Id = b.UserId
        LEFT JOIN PostAgg  p ON u.Id = p.UserId
    ),
    RankedUsers AS (
        SELECT
            Id,
            DisplayName,
            Reputation,
            GoldBadges,
            SilverBadges,
            BronzeBadges,
            QuestionCount,
            AnswerCount,
            AvgPostScore,
            LastPostDt,
            UserKey,
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
        WHERE ph.PostHistoryTypeId = 10
    ),
    UserLastClose AS (
        SELECT
            po.OwnerUserId AS UserId,
            rc.CloseReason,
            rc.CreationDate AS CloseDate
        FROM Posts po
        JOIN LATERAL (
            SELECT rc2.PostId, rc2.CreationDate, rc2.CloseReason
            FROM RecentClose rc2
            WHERE rc2.PostId = po.Id
            ORDER BY rc2.CreationDate DESC
            LIMIT 1
        ) rc ON true
    ),
    TopAnswers AS (
        SELECT
            p.OwnerUserId AS UserId,
            p.Title,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 2
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
    ta.Title AS TopAnswerTitle
FROM RankedUsers ru
LEFT JOIN UserLastClose ulc ON ru.Id = ulc.UserId
LEFT JOIN TopAnswers ta ON ta.UserId = ru.Id AND ta.rn = 1
WHERE ru.rn <= 100

UNION ALL

SELECT
    u.Id,
    COALESCE(u.DisplayName,'[deleted]') AS DisplayName,
    u.Reputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS QuestionCount,
    0 AS AnswerCount,
    NULL AS AvgPostScore,
    NULL AS LastPostDt,
    'No Activity' AS LastCloseReason,
    NULL AS TopAnswerTitle
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation >= 500

ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC
LIMIT 150;