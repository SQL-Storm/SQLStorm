WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(p.PostCount, 0)                AS PostCount,
        COALESCE(a.AnswerCount, 0)              AS AnswerCount,
        COALESCE(a.QuestionCount, 0)            AS QuestionCount,
        COALESCE(b.GoldBadge, 0)                AS GoldBadge,
        COALESCE(b.SilverBadge, 0)              AS SilverBadge,
        COALESCE(b.BronzeBadge, 0)              AS BronzeBadge,
        COALESCE(v.TotalVotes, 0)               AS TotalVotes,
        COALESCE(v.UpVotes, 0)                  AS UpVotes,
        COALESCE(v.DownVotes, 0)                AS DownVotes,
        COALESCE(c.LastCommentDate, TIMESTAMP '1970-01-01 00:00:00') AS LastCommentDate,
        COALESCE(l.LastLinkDate, TIMESTAMP '1970-01-01 00:00:00')    AS LastLinkDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(p.PostCount,0) DESC) AS RepRank
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) a ON u.Id = a.OwnerUserId
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadge,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadge,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadge
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT p.OwnerUserId,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
               COUNT(*)                                          AS TotalVotes
        FROM Posts p
        JOIN Votes v ON p.Id = v.PostId
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ) v ON u.Id = v.OwnerUserId
    LEFT JOIN (
        SELECT UserId, MAX(CreationDate) AS LastCommentDate
        FROM Comments
        GROUP BY UserId
    ) c ON u.Id = c.UserId
    LEFT JOIN (
        SELECT pl.PostId, MAX(pl.CreationDate) AS LastLinkDate
        FROM PostLinks pl
        GROUP BY pl.PostId
    ) l ON u.Id = l.PostId
)

-- Main rows
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.QuestionCount,
    us.AnswerCount,
    us.GoldBadge,
    us.SilverBadge,
    us.BronzeBadge,
    us.TotalVotes,
    us.UpVotes,
    us.DownVotes,
    us.RepRank,
    CASE
        WHEN us.LastCommentDate > us.LastLinkDate THEN us.LastCommentDate
        ELSE us.LastLinkDate
    END                                            AS LastActivity,
    ROUND(
        (us.Reputation * 0.4) +
        (us.PostCount   * 1.5) +
        (us.AnswerCount * 2)   +
        (us.GoldBadge   * 10)  +
        (us.SilverBadge * 5)   +
        (us.BronzeBadge * 2)   +
        ((us.UpVotes - us.DownVotes) * 0.1)
    , 2)                                           AS BenchmarkScore
FROM UserStats us
WHERE us.Reputation > 1000

UNION ALL

-- Totals row
SELECT
    CAST(NULL AS BIGINT)                           AS Id,
    'TOTAL'                                        AS DisplayName,
    SUM(us.Reputation)                             AS Reputation,
    SUM(us.PostCount)                              AS PostCount,
    SUM(us.QuestionCount)                          AS QuestionCount,
    SUM(us.AnswerCount)                            AS AnswerCount,
    SUM(us.GoldBadge)                              AS GoldBadge,
    SUM(us.SilverBadge)                            AS SilverBadge,
    SUM(us.BronzeBadge)                            AS BronzeBadge,
    SUM(us.TotalVotes)                             AS TotalVotes,
    SUM(us.UpVotes)                                AS UpVotes,
    SUM(us.DownVotes)                              AS DownVotes,
    CAST(NULL AS INTEGER)                          AS RepRank,
    CAST(NULL AS TIMESTAMP)                        AS LastActivity,
    ROUND(SUM(
        (us.Reputation * 0.4) +
        (us.PostCount   * 1.5) +
        (us.AnswerCount * 2)   +
        (us.GoldBadge   * 10)  +
        (us.SilverBadge * 5)   +
        (us.BronzeBadge * 2)   +
        ((us.UpVotes - us.DownVotes) * 0.1)
    ), 2)                                           AS BenchmarkScore
FROM UserStats us
WHERE us.Reputation > 1000
ORDER BY BenchmarkScore DESC
LIMIT 100 OFFSET 0;