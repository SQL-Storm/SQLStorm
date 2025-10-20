-- {"query": "54010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2588} 

WITH PostVotes AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1
                 WHEN vt.Name = 'DownMod' THEN -1
                 ELSE 0 END)            AS NetVotes,
        COUNT(CASE WHEN vt.Name = 'UpMod'  THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes
    FROM Posts p
    JOIN Votes v          ON v.PostId = p.Id
    JOIN VoteTypes vt     ON vt.Id = v.VoteTypeId
    GROUP BY p.Id
),
UserPosts AS (
    SELECT
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        p.Id                     AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        CASE WHEN p.ParentId IS NOT NULL
             THEN p.ParentId          -- for answers: question Id
             ELSE p.Id                 -- for questions
        END                        AS RefPostId,
        q.Id                      AS AcceptedAnswerOf      -- null if not accepted answer
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts q
        ON p.PostTypeId = 2
       AND p.ParentId   = q.Id
       AND q.AcceptedAnswerId = p.Id
),
UserStats AS (
    SELECT
        up.UserId,
        up.DisplayName,
        up.Reputation,
        SUM(CASE WHEN up.PostTypeId = 1 THEN 1 ELSE 0 END)            AS TotalQuestions,
        SUM(CASE WHEN up.PostTypeId = 2 THEN 1 ELSE 0 END)            AS TotalAnswers,
        SUM(CASE WHEN up.PostTypeId = 2 AND up.AcceptedAnswerOf IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(up.Score)                                               AS AvgScore,
        SUM(COALESCE(pv.NetVotes, 0))                               AS TotalVotesOnPosts
    FROM UserPosts up
    LEFT JOIN PostVotes pv ON pv.PostId = up.PostId
    GROUP BY up.UserId, up.DisplayName, up.Reputation
),
TagUsage AS (
    SELECT
        up.UserId,
        TRIM(LEADING '<' FROM TRIM(TRAILING '>' FROM tag)) AS TagName,
        COUNT(*)                                            AS TagCount
    FROM UserPosts up
    CROSS JOIN LATERAL
        regexp_split_to_table(up.Tags, '<>[>]+') AS tag
    GROUP BY up.UserId, TagName
),
TopTagPerUser AS (
    SELECT
        tu.UserId,
        tu.TagName   AS TopTag,
        tu.TagCount
    FROM (
        SELECT
            UserId,
            TagName,
            TagCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, TagName) AS rn
        FROM TagUsage
    ) tu
    WHERE tu.rn = 1
),
MonthlyAnswerRanks AS (
    SELECT
        up.UserId,
        DATE_TRUNC('month', up.CreationDate) AS Month,
        up.PostId                          AS AnswerId,
        up.Score,
        ROW_NUMBER() OVER (
            PARTITION BY up.UserId,
                         DATE_TRUNC('month', up.CreationDate)
            ORDER BY up.Score DESC, up.CreationDate
        ) AS Rank
    FROM UserPosts up
    WHERE up.PostTypeId = 2
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalQuestions,
    us.TotalAnswers,
    us.AcceptedAnswers,
    ROUND(us.AvgScore, 2)                  AS AvgScore,
    us.TotalVotesOnPosts,
    ttu.TopTag,
    ttu.TagCount,
   -m.Month,
    m.AnswerId,
    m.Score,
    m.Rank
FROM UserStats us
LEFT JOIN TopTagPerUser ttu ON ttu.UserId = us.UserId
LEFT JOIN MonthlyAnswerRanks m ON m.UserId = us.UserId
ORDER BY us.Reputation DESC, m.Month DESC, m.Rank
LIMIT 100;
