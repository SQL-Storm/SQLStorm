WITH
    u AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            u.LastAccessDate,
            COALESCE(u.Location, 'Unknown') AS Location,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
        FROM Users u
    ),
    b AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            COUNT(*)                                   AS TotalBadges,
            MAX(b.Date)                                AS LastBadgeDate
        FROM Badges b
        GROUP BY b.UserId
    ),
    p AS (
        SELECT
            p.OwnerUserId                                 AS UserId,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)  AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)  AS AnswerCount,
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)  AS AvgQuestionScore,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)  AS AvgAnswerScore,
            SUM(p.ViewCount)                              AS TotalViews,
            MAX(p.CreationDate)                           AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    v AS (
        SELECT
            p.OwnerUserId                                    AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived,
            COUNT(v.Id)                                      AS TotalVotesReceived
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    c AS (
        SELECT
            q.Id AS QuestionId,
            (
                SELECT ph.Comment
                FROM PostHistory ph
                WHERE ph.PostId = q.Id
                  AND ph.PostHistoryTypeId = 10
                  AND ph.Comment IS NOT NULL
                ORDER BY ph.CreationDate DESC
                FETCH FIRST 1 ROWS ONLY
            ) AS LastCloseReason
        FROM Posts q
        WHERE q.PostTypeId = 1
    ),
    c_owner AS (
        SELECT q.OwnerUserId, c.LastCloseReason
        FROM Posts q
        JOIN c ON c.QuestionId = q.Id
        WHERE q.OwnerUserId IS NOT NULL
    )
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.RepRank,
    COALESCE(b.GoldBadges, 0)   AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(p.QuestionCount, 0) AS Questions,
    COALESCE(p.AnswerCount, 0)   AS Answers,
    ROUND(COALESCE(p.AvgQuestionScore, 0), 2) AS AvgQScore,
    ROUND(COALESCE(p.AvgAnswerScore,   0), 2) AS AvgAScore,
    COALESCE(p.TotalViews, 0)   AS Views,
    COALESCE(v.UpVotesReceived, 0)   AS UpVotesRec,
    COALESCE(v.DownVotesReceived, 0) AS DownVotesRec,
    COALESCE(v.FavoritesReceived, 0) AS FavoritesRec,
    CASE
        WHEN COALESCE(v.DownVotesReceived, 0) = 0 THEN NULL
        ELSE ROUND(
            (COALESCE(v.UpVotesReceived, 0) * 1.0) /
            COALESCE(v.DownVotesReceived, 0)
        , 2)
    END AS UpDownRatio,
    u.Location,
    u.CreationDate,
    u.LastAccessDate,
    p.LastPostDate,
    b.LastBadgeDate,
    STRING_AGG(COALESCE(c_owner.LastCloseReason, 'None'), '; ')
        FILTER (WHERE c_owner.LastCloseReason IS NOT NULL) AS RecentCloseReasons
FROM u
LEFT JOIN b ON b.UserId = u.Id
LEFT JOIN p ON p.UserId = u.Id
LEFT JOIN v ON v.UserId = u.Id
LEFT JOIN c_owner ON c_owner.OwnerUserId = u.Id
WHERE u.Reputation > 1000
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.RepRank,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    p.QuestionCount,
    p.AnswerCount,
    p.AvgQuestionScore,
    p.AvgAnswerScore,
    p.TotalViews,
    p.LastPostDate,
    v.UpVotesReceived,
    v.DownVotesReceived,
    v.FavoritesReceived,
    b.LastBadgeDate,
    u.Location,
    u.CreationDate,
    u.LastAccessDate
ORDER BY u.RepRank
FETCH FIRST 100 ROWS ONLY
OFFSET 0;