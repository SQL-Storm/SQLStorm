-- {"query": "3222.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2439} 

WITH
    -- Base user info with rank by reputation
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
    -- Badge aggregates per user
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
    -- Post aggregates per user
    p AS (
        SELECT
            p.OwnerUserId                                 AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)  AS AvgQuestionScore,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)  AS AvgAnswerScore,
            SUM(p.ViewCount)                              AS TotalViews,
            MAX(p.CreationDate)                           AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    -- Vote aggregates per user (votes received on their posts)
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
    -- Latest close reason per question (correlated subquery)
    c AS (
        SELECT
            q.Id AS QuestionId,
            (
                SELECT ph.Comment
                FROM PostHistory ph
                WHERE ph.PostId = q.Id
                  AND ph.PostHistoryTypeId = 10   -- Post Closed
                  AND ph.Comment IS NOT NULL
                ORDER BY ph.CreationDate DESC
                LIMIT 1
            ) AS LastCloseReason
        FROM Posts q
        WHERE q.PostTypeId = 1
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
    ROUND(COALESCE(p.AvgQuestionScore, 0)::numeric, 2) AS AvgQScore,
    ROUND(COALESCE(p.AvgAnswerScore,   0)::numeric, 2) AS AvgAScore,
    COALESCE(p.TotalViews, 0)   AS Views,
    COALESCE(v.UpVotesReceived, 0)   AS UpVotesRec,
    COALESCE(v.DownVotesReceived, 0) AS DownVotesRec,
    COALESCE(v.FavoritesReceived, 0) AS FavoritesRec,
    CASE
        WHEN COALESCE(v.DownVotesReceived, 0) = 0 THEN NULL
        ELSE ROUND((COALESCE(v.UpVotesReceived, 0)::numeric /
                    COALESCE(v.DownVotesReceived, 0)), 2)
    END AS UpDownRatio,
    u.Location,
    u.CreationDate,
    u.LastAccessDate,
    p.LastPostDate,
    b.LastBadgeDate,
    STRING_AGG(DISTINCT COALESCE(c.LastCloseReason, 'None'), '; ')
        FILTER (WHERE c.LastCloseReason IS NOT NULL)
        OVER (PARTITION BY u.Id) AS RecentCloseReasons
FROM u
LEFT JOIN b ON b.UserId = u.Id
LEFT JOIN p ON p.UserId = u.Id
LEFT JOIN v ON v.UserId = u.Id
LEFT JOIN (
    SELECT q.OwnerUserId, c.LastCloseReason
    FROM Posts q
    JOIN c ON c.QuestionId = q.Id
    WHERE q.OwnerUserId IS NOT NULL
) AS c ON c.OwnerUserId = u.Id
WHERE u.Reputation > 1000
ORDER BY u.RepRank
LIMIT 100
OFFSET 0;
