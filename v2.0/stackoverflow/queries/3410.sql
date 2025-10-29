-- {"query": "3410.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1664}
WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
    FROM Users u
),
UserTagContrib AS (
    SELECT 
        p.OwnerUserId AS UserId,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM token)) AS Tag,
        COUNT(*) AS PostsWithTag
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(TRIM(BOTH '<' FROM p.Tags), '><') AS token
    ) s
    WHERE p.PostTypeId = 2
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM token))
),
TopTagPerUser AS (
    SELECT 
        utc.UserId,
        utc.Tag,
        utc.PostsWithTag,
        ROW_NUMBER() OVER (PARTITION BY utc.UserId ORDER BY utc.PostsWithTag DESC) AS rn
    FROM UserTagContrib utc
),
RecentVotes AS (
    SELECT 
        v.UserId,
        MAX(v.CreationDate) AS LastVoteDate,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.AnswerCount,
        us.QuestionCount,
        us.BadgeCount,
        COALESCE(rv.UpVotesGiven, 0) AS UpVotesGiven,
        COALESCE(rv.DownVotesGiven, 0) AS DownVotesGiven,
        rv.LastVoteDate,
        tt.Tag,
        tt.PostsWithTag
    FROM UserStats us
    LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
    LEFT JOIN (
        SELECT UserId, Tag, PostsWithTag
        FROM TopTagPerUser
        WHERE rn = 1
    ) tt ON tt.UserId = us.Id
),
Filtered AS (
    SELECT 
        c.Id,
        c.DisplayName,
        c.Reputation,
        c.AnswerCount,
        c.QuestionCount,
        c.BadgeCount,
        c.UpVotesGiven,
        c.DownVotesGiven,
        c.LastVoteDate,
        c.Tag,
        c.PostsWithTag
    FROM Combined c
    WHERE 
          c.Reputation > 10000
       OR (
           c.AnswerCount > 0 
           AND (
                SELECT AVG(CAST(p.Score AS NUMERIC))
                FROM Posts p
                WHERE p.OwnerUserId = c.Id 
                  AND p.PostTypeId = 2
               ) > 5
          )
)
SELECT 
    f.Id,
    f.DisplayName,
    f.Reputation,
    f.AnswerCount,
    f.QuestionCount,
    f.BadgeCount,
    f.UpVotesGiven,
    f.DownVotesGiven,
    f.LastVoteDate,
    f.Tag,
    f.PostsWithTag
FROM Filtered f

UNION ALL

SELECT
    -1 AS Id,
    'Community' AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS AnswerCount,
    CAST(NULL AS INTEGER) AS QuestionCount,
    CAST(NULL AS INTEGER) AS BadgeCount,
    CAST(NULL AS INTEGER) AS UpVotesGiven,
    CAST(NULL AS INTEGER) AS DownVotesGiven,
    CAST(NULL AS TIMESTAMP) AS LastVoteDate,
    CAST(NULL AS VARCHAR(255)) AS Tag,
    CAST(NULL AS INTEGER) AS PostsWithTag
WHERE NOT EXISTS (SELECT 1 FROM Combined)
ORDER BY Reputation DESC NULLS LAST, AnswerCount DESC NULLS LAST
LIMIT 100;