-- {"query": "25049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3867} 

WITH RECURSIVE TagExploded AS (
    SELECT
        p.Id               AS PostId,
        UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
TagStats AS (
    SELECT
        Tag,
        COUNT(*)                           AS PostCnt,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
    FROM TagExploded
    GROUP BY Tag
),
UserStats AS (
    SELECT
        u.Id                                      AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCnt,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCnt,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT b.Id)                       AS BadgeCnt,
        MAX(p.CreationDate)                        AS LastPostDate
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserTagScore AS (
    SELECT
        us.UserId,
        SUM(CASE WHEN ts.rn <= 5 THEN 10 ELSE 2 END) AS TagScore
    FROM UserStats us
    LEFT JOIN Posts p ON p.OwnerUserId = us.UserId
    LEFT JOIN TagExploded te ON te.PostId = p.Id
    LEFT JOIN TagStats ts ON ts.Tag = te.Tag
    GROUP BY us.UserId
),
TopUsers AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCnt,
        us.AnswerCnt,
        us.UpVotes,
        us.DownVotes,
        us.BadgeCnt,
        us.LastPostDate,
        COALESCE(uts.TagScore, 0)                               AS TagScore,
        (us.UpVotes - us.DownVotes)                             AS NetScore,
        CASE
            WHEN us.Reputation >= 25000 THEN 'Guru'
            WHEN us.Reputation >= 15000 THEN 'Master'
            WHEN us.Reputation >= 5000  THEN 'Contributor'
            ELSE 'Starter'
        END                                                      AS Tier,
        (SELECT COUNT(*) FROM Posts p2
         WHERE p2.OwnerUserId = us.UserId
           AND p2.PostTypeId = 2
           AND p2.Score >= 10)                                 AS HighScoringAnswers,
        (SELECT COUNT(*) FROM Comments c
         WHERE c.UserId = us.UserId
           AND c.Score IS NULL)                                 AS NullScoreComments
    FROM UserStats us
    LEFT JOIN UserTagScore uts ON uts.UserId = us.UserId
    WHERE (us.QuestionCnt + us.AnswerCnt) > 0
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCnt,
    tu.AnswerCnt,
    tu.UpVotes,
    tu.DownVotes,
    tu.BadgeCnt,
    tu.LastPostDate,
    tu.TagScore,
    tu.NetScore,
    tu.Tier,
    tu.HighScoringAnswers,
    tu.NullScoreComments
FROM TopUsers tu
WHERE tu.NetScore IS NOT NULL
ORDER BY tu.NetScore DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    NULL::int          AS QuestionCnt,
    NULL::int          AS AnswerCnt,
    NULL::int          AS UpVotes,
    NULL::int          AS DownVotes,
    NULL::int          AS BadgeCnt,
    NULL::timestamp    AS LastPostDate,
    NULL::int          AS TagScore,
    NULL::int          AS NetScore,
    NULL::varchar(20)  AS Tier,
    NULL::int          AS HighScoringAnswers,
    NULL::int          AS NullScoreComments
FROM (
    SELECT b.UserId, us.DisplayName, us.Reputation
    FROM Badges b
    JOIN Users us ON us.Id = b.UserId
    EXCEPT
    SELECT p.OwnerUserId, u2.DisplayName, u2.Reputation
    FROM Posts p
    JOIN Users u2 ON u2.Id = p.OwnerUserId
) u
OFFSET 0;
