WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                      AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                      AS AnswerCount,
        SUM(p.Score)                                                     AS TotalScore,
        AVG(p.Score)                                                     AS AvgScore,
        MAX(p.CreationDate)                                              AS LastPostDate,
        COUNT(v.Id)                                                       AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)                 AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)                 AS DownVotes,
        COUNT(b.Id)                                                       AS BadgeCount
    FROM Users u
    LEFT JOIN Posts         p  ON p.OwnerUserId   = u.Id
    LEFT JOIN Votes         v  ON v.PostId        = p.Id
    LEFT JOIN Badges        b  ON b.UserId        = u.Id
    WHERE p.PostTypeId IN (1,2,3)
    GROUP BY u.Id, u.DisplayName
),
RankedUsers AS (
    SELECT
        *,
        RANK() OVER (ORDER BY TotalScore DESC)          AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY TotalScore DESC) AS ScorePercentile
    FROM UserActivity
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.QuestionCount AS QuitCount,
    ru.AnswerCount,
    ru.TotalScore,
    ru.AvgScore,
    ru.LastPostDate,
    ru.TotalVotes,
    ru.UpVotes,
    ru.DownVotes,
    ru.BadgeCount,
    ru.ScoreRank,
    ru.ScorePercentile
FROM RankedUsers ru
ORDER BY ru.TotalScore DESC
LIMIT 1000;