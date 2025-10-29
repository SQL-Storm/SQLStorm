WITH UserAnswerStats AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT a.Id)              AS AnswerCount,
        SUM(COALESCE(a.Score,0))          AS TotalAnswerScore,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
        MAX(a.CreationDate)               AS LastAnswerDate
    FROM Users u
    LEFT JOIN Posts a
        ON a.OwnerUserId = u.Id
       AND a.PostTypeId = 2
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*)                                 AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagAnswerCounts AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT a.Id) AS AnswersWithTag,
        SUM(COALESCE(a.Score,0)) AS TagScore
    FROM Tags t
    JOIN PostLinks pl
        ON pl.RelatedPostId IN (t.ExcerptPostId, t.WikiPostId)
    JOIN Posts a
        ON a.Id = pl.PostId
       AND a.PostTypeId = 2
    GROUP BY t.TagName
),
RecentUserActivity AS (
    SELECT
        u.Id                     AS UserId,
        MAX(COALESCE(p.LastEditDate, p.CreationDate)) AS LastActivity
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
MainResults AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.AnswerCount,
        uas.TotalAnswerScore,
        uas.AvgAnswerScore,
        COALESCE(ub.GoldBadges,0)   AS GoldBadges,
        COALESCE(ub.SilverBadges,0) AS SilverBadges,
        COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ub.TotalBadges,0)  AS TotalBadges,
        rua.LastActivity,
        ROW_NUMBER() OVER (ORDER BY uas.TotalAnswerScore DESC) AS ScoreRank,
        COALESCE(tac.TagName,'NoTag')            AS TopTag,
        COALESCE(tac.AnswersWithTag,0)           AS TagAnswerCount,
        COALESCE(tac.TagScore,0)                 AS TagScore
    FROM UserAnswerStats uas
    LEFT JOIN UserBadgeStats ub
        ON ub.UserId = uas.UserId
    LEFT JOIN RecentUserActivity rua
        ON rua.UserId = uas.UserId
    LEFT JOIN (
        SELECT ua.UserId, t.TagName, t.AnswersWithTag, t.TagScore
        FROM UserAnswerStats ua
        CROSS JOIN LATERAL (
            SELECT t.TagName, t.AnswersWithTag, t.TagScore
            FROM TagAnswerCounts t
            WHERE t.TagScore > 0
            ORDER BY t.TagScore DESC
            LIMIT 1
        ) t
    ) tac ON tac.UserId = uas.UserId
    WHERE uas.TotalAnswerScore > 0
      AND (uas.Reputation / NULLIF(uas.AnswerCount,0)) > 10
      AND NOT EXISTS (
            SELECT 1
            FROM Posts q
            WHERE q.OwnerUserId = uas.UserId
              AND q.PostTypeId = 1
              AND q.ClosedDate IS NOT NULL
          )
      AND EXISTS (
            SELECT 1
            FROM Posts q
            JOIN Posts a ON a.ParentId = q.Id
            WHERE a.OwnerUserId = uas.UserId
              AND q.Tags LIKE '%<sql>%'
          )
)
SELECT *
FROM MainResults
WHERE TotalAnswerScore > 0

UNION ALL

SELECT
    NULL AS UserId,
    'Aggregate' AS DisplayName,
    NULL AS Reputation,
    SUM(AnswerCount)          AS AnswerCount,
    SUM(TotalAnswerScore)     AS TotalAnswerScore,
    AVG(AvgAnswerScore)       AS AvgAnswerScore,
    SUM(GoldBadges)           AS GoldBadges,
    SUM(SilverBadges)         AS SilverBadges,
    SUM(BronzeBadges)         AS BronzeBadges,
    SUM(TotalBadges)          AS TotalBadges,
    MAX(LastActivity)         AS LastActivity,
    NULL                      AS ScoreRank,
    NULL                      AS TopTag,
    NULL                      AS TagAnswerCount,
    NULL                      AS TagScore
FROM MainResults;