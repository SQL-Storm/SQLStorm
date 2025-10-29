WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                       FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id)                       FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score)                     FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        MAX(
            CASE 
                WHEN p.PostTypeId = 1 THEN p.Title 
            END
        ) FILTER (WHERE p.CreationDate = (
            SELECT MAX(p2.CreationDate)
            FROM Posts p2
            WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
        )) AS LatestQuestionTitle,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) AS GoldBadgeCount
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagRanks AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
TopTags AS (
    SELECT TagName, Count
    FROM TagRanks
    WHERE rn <= 5
),
RecentVote AS (
    SELECT 
        v.UserId,
        MAX(v.CreationDate)                                           AS LastVoteDate,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')                     AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')                   AS DownVotesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
TagSummary AS (
    SELECT STRING_AGG(t.TagName || ' ('|| t.Count ||')', '; ') AS Top5Tags
    FROM TopTags t
)

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(CAST(us.AvgQuestionScore AS numeric),2)                       AS AvgQScore,
    us.GoldBadgeCount,
    us.LatestQuestionTitle,
    COALESCE(rv.LastVoteDate, CAST('1970-01-01 00:00:00' AS timestamp))                AS LastVoteDate,
    rv.UpVotesGiven,
    rv.DownVotesGiven,
    tg.Top5Tags
FROM UserStats us
LEFT JOIN RecentVote rv   ON rv.UserId = us.Id
CROSS JOIN (SELECT Top5Tags FROM TagSummary) tg
UNION ALL
SELECT 
    NULL        AS Id,
    'Tag Summary' AS DisplayName,
    NULL        AS Reputation,
    NULL        AS QuestionCount,
    NULL        AS AnswerCount,
    NULL        AS AvgQScore,
    NULL        AS GoldBadgeCount,
    NULL        AS LatestQuestionTitle,
    NULL        AS LastVoteDate,
    NULL        AS UpVotesGiven,
    NULL        AS DownVotesGiven,
    ts.Top5Tags
FROM TagSummary ts
ORDER BY Id NULLS FIRST, DisplayName;