WITH UserScoreRanking AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROUND((
            COALESCE(SUM(COALESCE(p.Score, 0)) + SUM(COALESCE(vb.VoteScore, 0)), 0) *
            CASE WHEN MAX(u.Reputation) > 0
                 THEN LEAST(1.0, u.Reputation / NULLIF(MAX(u.Reputation) OVER (), 0))
                 ELSE 0.1 END), 2) AS UserWeightedScore,
        avat.WindowsVoteSum AS VotesTrailing90Days,
        u.AccountId
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT pv.Id AS PostId,
               SUM(CASE
                       WHEN v.VoteTypeId IN (2) THEN 1
                       WHEN v.VoteTypeId IN (3, 4) THEN -1
                       ELSE 0
                   END) AS VoteScore
        FROM Posts pv
        JOIN Votes v ON v.PostId = pv.Id
        GROUP BY pv.Id
    ) vb ON vb.PostId = p.Id
    LEFT JOIN (
        SELECT vouter.UserId,
               SUM(CASE
                       WHEN vouter.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '90' DAY THEN 1
                       ELSE 0
                   END) AS WindowsVoteSum
        FROM Votes vouter
        GROUP BY vouter.UserId
    ) avat ON avat.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        avat.WindowsVoteSum,
        u.AccountId
)
SELECT *
FROM UserScoreRanking;