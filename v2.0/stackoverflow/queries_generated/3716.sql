-- {"query": "3716.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1846} 

/*  Complex benchmark query on the StackOverflow schema  */
WITH 
/*-------------------------------------------------------
  User‑level aggregates including conditional counts,
  averages, latest question title and gold‑badge total
-------------------------------------------------------*/
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

/*-------------------------------------------------------
  Tag ranking – keep only the five most used tags
-------------------------------------------------------*/
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

/*-------------------------------------------------------
  Latest voting activity per user (correlated sub‑query)
-------------------------------------------------------*/
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

/*-------------------------------------------------------
  One‑row summary of the top five tags (used in the UNION)
-------------------------------------------------------*/
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
    ROUND(us.AvgQuestionScore::numeric,2)                       AS AvgQScore,
    us.GoldBadgeCount,
    us.LatestQuestionTitle,
    COALESCE(rv.LastVoteDate, TIMESTAMP 'epoch')                AS LastVoteDate,
    rv.UpVotesGiven,
    rv.DownVotesGiven,
    tg.Top5Tags
FROM UserStats us
LEFT JOIN RecentVote rv   ON rv.UserId = us.Id
CROSS JOIN (SELECT Top5Tags FROM TopTags) tg
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
