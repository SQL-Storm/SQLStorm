-- {"query": "24100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3129} 

/* Read‑heavy, mixed joins, window functions, set operators, correlated subqueries,
   NULL handling and string manipulation – ideal for a benchmark test. */

WITH active_users AS (
    /* users with moderate reputation but a lot of activity */
    SELECT u.Id         AS UserId,
           u.Reputation,
           u.CreationDate,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCnt,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCnt,
           COALESCE(SUM(p.Score),0)                  AS TotalScore,
           COALESCE(cnt.badges,0)                    AS BadgeCnt,
           STRING_AGG(DISTINCT tt.TagName, '|')      AS TagStr
    FROM  Users u
      LEFT JOIN Posts      p ON p.OwnerUserId = u.Id
      LEFT JOIN Badges     b ON b.UserId        = u.Id
      LEFT JOIN Tags       t ON t.Id            = p.Id
      -- explode the tags array for question posts only
      LEFT JOIN LATERAL (
            SELECT unnest(regexp_split_to_array(p.Tags,'><')) AS TagVal
        ) dt ON p.PostTypeId = 1
      LEFT JOIN Tags tt  ON tt.TagName = dt.TagVal
      LEFT JOIN (SELECT UserId, COUNT(*) AS badges
                 FROM Badges GROUP BY UserId) cnt
        ON cnt.UserId = u.Id
    WHERE u.Reputation >= 500   -- active
    GROUP BY u.Id, u.Reputation, u.CreationDate, cnt.badges
    HAVING COUNT(p.Id) > 50
),

inactive_users AS (
    /* users with high reputation but low daily activity – to test
       outer‑join/NULL logic together with set union */
    SELECT u.Id         AS UserId,
           u.Reputation,
           u.CreationDate,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCnt,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCnt,
           COALESCE(SUM(p.Score),0)                  AS TotalScore,
           COALESCE(cnt.badges,0)                    AS BadgeCnt,
           STRING_AGG(DISTINCT tt.TagName, '|')      AS TagStr
    FROM  Users u
      LEFT JOIN Posts      p ON p.OwnerUserId = u.Id
      LEFT JOIN Badges     b ON b.UserId        = u.Id
      LEFT JOIN Tags       t ON t.Id            = p.Id
      LEFT JOIN LATERAL (
            SELECT unnest(regexp_split_to_array(p.Tags,'><')) AS TagVal
        ) dt ON p.PostTypeId = 1
      LEFT JOIN Tags tt  ON tt.TagName = dt.TagVal
      LEFT JOIN (SELECT UserId, COUNT(*) AS badges
                 FROM Badges GROUP BY UserId) cnt
        ON cnt.UserId = u.Id
    WHERE u.Reputation >= 2000      -- high rep
      AND u.LastAccessDate < NOW() - INTERVAL '90 DAY'   -- inactive
    GROUP BY u.Id, u.Reputation, u.CreationDate, cnt.badges
    HAVING COUNT(p.Id) < 10
),

all_users AS (
    /* UNION ALL preserves duplicates – useful for set‑operator tests */
    SELECT * FROM active_users
    UNION ALL
    SELECT * FROM inactive_users
),

tag_rank AS (
    /* window functions calculate per‑tag and global rankings */
    SELECT au.*,
           ROW_NUMBER() OVER (PARTITION BY TagStr ORDER BY Reputation DESC) AS TagRank,
           RANK()       OVER (ORDER BY Reputation DESC)                        AS GlobalRank
    FROM   all_users au
),

last_vote AS (
    /* correlated sub‑query that fetches the most recent vote on the
       user's latest answer */
    SELECT tr.*,
           (SELECT MAX(v.CreationDate)
              FROM Votes v
             WHERE v.PostId IN (
                   SELECT p.Id
                     FROM Posts p
                    WHERE p.OwnerUserId = tr.UserId
                      AND p.PostTypeId = 2
                )
           ) AS LastVoteDate
    FROM tag_rank tr
)

SELECT lv.UserId,
       lv.Reputation,
       lv.QuestionCnt,
       lv.AnswerCnt,
       lv.TotalScore,
       lv.BadgeCnt,
       lv.TagStr,
       lv.TagRank,
       lv.GlobalRank,
       CASE
           WHEN lv.Reputation > 10000 THEN 'Elite'
           WHEN lv.Reputation BETWEEN 5000 AND 9999 THEN 'Pro'
           ELSE 'Regular'
       END                           AS RankTier,
       COALESCE(TO_CHAR(lv.LastVoteDate, 'YYYY-MM-DD'), 'Never') AS LatestVote,
       CASE
           WHEN lv.AnswerCnt = 0 THEN NULL
           ELSE 'Answered ' || lv.AnswerCnt || ' posts'
       END                           AS AnswerSummary
FROM last_vote lv
WHERE lv.GlobalRank <= 200          -- limit output size for benchmark
ORDER BY lv.GlobalRank, lv.Reputation DESC;
