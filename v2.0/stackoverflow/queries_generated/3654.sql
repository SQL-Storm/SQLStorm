-- {"query": "3654.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2112} 

WITH
    -- Aggregate user activity and badge information
    UserStats AS (
        SELECT
            u.Id                                           AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id)          FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id)          FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            COUNT(b.Id)                                          AS BadgeCount,
            SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 10 END) AS BadgeScore,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)       AS RepRank
        FROM Users u
        LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
        LEFT JOIN Badges   b ON b.UserId      = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    -- Tag usage statistics (questions only)
    TagUsage AS (
        SELECT
            t.TagName,
            COUNT(pt.Id)                                   AS QuestionUses,
            COUNT(DISTINCT pt.OwnerUserId)                 AS DistinctAuthors,
            STRING_AGG(DISTINCT pt.Title, '; ') 
                FILTER (WHERE pt.Title IS NOT NULL)       AS SampleTitles
        FROM Tags t
        JOIN Posts pt
          ON pt.Tags LIKE CONCAT('%<', t.TagName, '>%')
         AND pt.PostTypeId = 1
        GROUP BY t.TagName
        HAVING COUNT(pt.Id) > 1000
    ),

    -- Top posts per type (question/answer) with ranking
    TopPosts AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            p.ViewCount,
            p.CreationDate,
            p.PostTypeId,
            u.DisplayName                                   AS OwnerName,
            ROW_NUMBER() OVER (
                PARTITION BY p.PostTypeId
                ORDER BY p.Score DESC, p.ViewCount DESC
            )                                                AS RankInType
        FROM Posts p
        LEFT JOIN Users u ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId IN (1, 2)          -- questions & answers
    ),

    -- Most recent close events (with reason)
    RecentClosed AS (
        SELECT
            ph.PostId,
            ph.CreationDate                                 AS ClosedDate,
            CAST(ph.Comment AS INT)                         AS CloseReasonId,
            ct.Name                                          AS CloseReason,
            COUNT(*) OVER (PARTITION BY ph.PostId)          AS CloseVoteCount
        FROM PostHistory ph
        JOIN CloseReasonTypes ct ON ct.Id = CAST(ph.Comment AS INT)
        WHERE ph.PostHistoryTypeId = 10                    -- Post Closed
    ),

    -- Vote aggregates per post
    AggVotes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1
                     WHEN vt.Id = 3 THEN -1
                     ELSE 0 END)                        AS NetScore,
            COUNT(*) FILTER (WHERE vt.Id = 5)              AS FavoriteCount,
            MAX(v.CreationDate)                            AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    )

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.BadgeCount,
    us.BadgeScore,
    us.RepRank,

    -- top‑scoring question for the user
    tp.Title                                 AS TopQuestionTitle,
    tp.Score                                 AS TopQuestionScore,
    tp.ViewCount                             AS TopQuestionViews,
    tp.CreationDate                          AS TopQuestionDate,

    -- representative tag data (joined via a heuristic)
    tu.TagName,
    tu.QuestionUses,
    tu.DistinctAuthors,
    tu.SampleTitles,

    -- post status derived from recent close events
    CASE WHEN rc.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS PostStatus,
    rc.CloseReason,

    -- vote delta between aggregated votes and post score
    COALESCE(av.NetScore, 0) - COALESCE(tp.Score, 0) AS ScoreDelta,

    -- last activity derived from votes
    av.LastVoteDate

FROM UserStats us
LEFT JOIN TopPosts tp
       ON tp.OwnerName = us.DisplayName
      AND tp.PostTypeId = 1               -- only questions
      AND tp.RankInType = 1               -- the very top one per user
LEFT JOIN TagUsage tu
       ON tu.DistinctAuthors > 10         -- only popular tags
LEFT JOIN RecentClosed rc
       ON rc.PostId = tp.Id
LEFT JOIN AggVotes av
       ON av.PostId = tp.Id
WHERE us.RepRank <= 100
  AND (us.BadgeScore > 200 OR us.QuestionCount > 50)
ORDER BY us.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT 1) AS dummy
WHERE FALSE;
