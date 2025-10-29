-- {"query": "3771.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2094} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(qc.QuestionCnt, 0)            AS QuestionCnt,
        COALESCE(ac.AnswerCnt, 0)             AS AnswerCnt,
        COALESCE(bc.GoldCnt,   0)              AS GoldCnt,
        COALESCE(bc.SilverCnt, 0)              AS SilverCnt,
        COALESCE(bc.BronzeCnt, 0)              AS BronzeCnt,
        COALESCE(vu.UpVotes, 0) - COALESCE(vu.DownVotes, 0) AS NetVoteScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCnt,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCnt
        FROM Posts
        GROUP BY OwnerUserId
    ) qc ON u.Id = qc.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCnt
        FROM Posts
        GROUP BY OwnerUserId
    ) ac ON u.Id = ac.OwnerUserId
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Badges
        GROUP BY UserId
    ) bc ON u.Id = bc.UserId
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY UserId
    ) vu ON u.Id = vu.UserId
),

TagUsage AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QPosts,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS APosts,
        AVG(p.Score)                              AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Id IS NOT NULL) AS TopContributors
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT *
        FROM Posts p
        WHERE p.Tags ILIKE concat('%<', t.TagName, '>%')
    ) p ON true
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 0
),

RandomTagForUser AS (
    SELECT
        us.Id,
        (SELECT unnest(string_to_array(us.DisplayName, ' '))
         ORDER BY random()
         LIMIT 1) AS RandomWord
    FROM UserStats us
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCnt,
    us.AnswerCnt,
    us.GoldCnt,
    us.SilverCnt,
    us.BronzeCnt,
    us.NetVoteScore,
    us.RepRank,
    tu.TagName,
    tu.QPosts,
    tu.APosts,
    tu.AvgScore,
    tu.TopContributors
FROM UserStats us
LEFT JOIN RandomTagForUser rtu ON rtu.Id = us.Id
LEFT JOIN TagUsage tu
       ON tu.TagName = rtu.RandomWord
WHERE us.Reputation > 1000
  AND (us.QuestionCnt + us.AnswerCnt) > 10
  AND NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
          AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
          AND p.PostTypeId = 1
          AND p.Title IS NULL
    )
ORDER BY us.RepRank
LIMIT 100

UNION ALL

SELECT
    NULL AS Id,
    'Aggregate Summary' AS DisplayName,
    NULL AS Reputation,
    SUM(QuestionCnt)      AS QuestionCnt,
    SUM(AnswerCnt)        AS AnswerCnt,
    SUM(GoldCnt)          AS GoldCnt,
    SUM(SilverCnt)        AS SilverCnt,
    SUM(BronzeCnt)        AS BronzeCnt,
    SUM(NetVoteScore)     AS NetVoteScore,
    NULL                  AS RepRank,
    NULL                  AS TagName,
    NULL                  AS QPosts,
    NULL                  AS APosts,
    NULL                  AS AvgScore,
    NULL                  AS TopContributors
FROM UserStats
WHERE Reputation > 5000;
