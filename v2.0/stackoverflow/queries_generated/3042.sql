-- {"query": "3042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1575} 

/*  Benchmark query – heavy use of CTEs, window functions, outer joins, 
    correlated subqueries, set operators, complex predicates and NULL logic */
WITH
    /* 1️⃣ Users with at least one gold badge and their total reputation */
    GoldBadgeUsers AS (
        SELECT  u.Id                              AS UserId,
                u.DisplayName,
                u.Reputation,
                COUNT(b.Id)                       AS GoldBadgeCount,
                MAX(b.Date)                       AS LastGoldBadgeDate
        FROM    Users u
        LEFT JOIN Badges b
               ON b.UserId = u.Id
              AND b.Class = 1                       -- gold badge
        GROUP BY u.Id, u.DisplayName, u.Reputation
        HAVING COUNT(b.Id) > 0
    ),

    /* 2️⃣ Aggregate post statistics per user (questions & answers) */
    UserPostStats AS (
        SELECT  p.OwnerUserId                              AS UserId,
                COUNT(*) FILTER (WHERE p.PostTypeId = 1)   AS QuestionCount,
                COUNT(*) FILTER (WHERE p.PostTypeId = 2)   AS AnswerCount,
                SUM(p.Score)                               AS TotalScore,
                MAX(p.CreationDate)                        AS LastPostDate,
                SUM(p.ViewCount)                           AS TotalViews,
                AVG(p.FavoriteCount)                       AS AvgFavorites,
                STRING_AGG(DISTINCT pt.Name, ',')           AS PostTypeList
        FROM    Posts p
        LEFT JOIN PostTypes pt
               ON pt.Id = p.PostTypeId
        WHERE   p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    /* 3️⃣ Latest activity per user (most recent comment or post edit) */
    LatestActivity AS (
        SELECT  ua.UserId,
                GREATEST(
                    COALESCE(up.LastPostDate, TIMESTAMP '1970-01-01'),
                    COALESCE(lc.LastCommentDate, TIMESTAMP '1970-01-01')
                )                                            AS LastActivityTimestamp
        FROM    UserPostStats ua
        LEFT JOIN LATERAL (
            SELECT MAX(c.CreationDate) AS LastCommentDate
            FROM   Comments c
            WHERE  c.UserId = ua.UserId
        ) lc ON TRUE
    ),

    /* 4️⃣ Vote aggregates (up/down votes) with window ranking */
    VoteAggregates AS (
        SELECT  v.PostId,
                p.OwnerUserId                                            AS UserId,
                SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)               AS UpVotes,
                SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)               AS DownVotes,
                ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                                   ORDER BY SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) DESC) AS RankByUpVotes
        FROM    Votes v
        JOIN    Posts p            ON p.Id = v.PostId
        JOIN    VoteTypes vt       ON vt.Id = v.VoteTypeId
        WHERE   vt.Id IN (2,3)     -- UpMod or DownMod
        GROUP BY v.PostId, p.OwnerUserId
    ),

    /* 5️⃣ Users that have both gold badges and at least 100 total posts (union for benchmarking) */
    QualifiedUsers AS (
        SELECT  gb.UserId,
                gb.DisplayName,
                gb.Reputation,
                gb.GoldBadgeCount,
                gps.QuestionCount,
                gps.AnswerCount,
                va.UpVotes,
                va.DownVotes,
                la.LastActivityTimestamp,
                ROW_NUMBER() OVER (ORDER BY gb.Reputation DESC, gps.TotalScore DESC) AS OverallRank
        FROM    GoldBadgeUsers gb
        JOIN    UserPostStats gps       ON gps.UserId = gb.UserId
        LEFT JOIN VoteAggregates va    ON va.UserId = gb.UserId
        LEFT JOIN LatestActivity la    ON la.UserId = gb.UserId
        WHERE   (gps.QuestionCount + gps.AnswerCount) >= 100
          AND   COALESCE(va.UpVotes,0) - COALESCE(va.DownVotes,0) > 0
    ),

    /* 6️⃣ Complement set: users with no gold badges but with high answer acceptance ratio */
    HighAcceptanceNonGold AS (
        SELECT  u.Id                         AS UserId,
                u.DisplayName,
                u.Reputation,
                COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                                      AS AnswerCount,
                SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)                 AS AcceptedAnswers,
                CASE WHEN COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) = 0 THEN NULL
                     ELSE ROUND(100.0 *
                         SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) /
                         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2), 2)
                END                                                                            AS AcceptancePct,
                ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                                 AS RankByReputation
        FROM    Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        WHERE   NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
        GROUP BY u.Id, u.DisplayName, u.Reputation
        HAVING  COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) >= 50
           AND  (SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) * 1.0) /
                NULLIF(COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2),0) >= 0.25
    )

/* Final result – union of the two heavy‑weight sets with ordering and pagination */
SELECT *
FROM (
    SELECT  q.UserId,
            q.DisplayName,
            q.Reputation,
            q.GoldBadgeCount,
            q.QuestionCount,
            q.AnswerCount,
            q.UpVotes,
            q.DownVotes,
            q.LastActivityTimestamp,
            q.OverallRank                                 AS Rank,
            'Gold+Active'                                 AS Category
    FROM    QualifiedUsers q

    UNION ALL

    SELECT  h.UserId,
            h.DisplayName,
            h.Reputation,
            0                                            AS GoldBadgeCount,
            0                                            AS QuestionCount,
            h.AnswerCount,
            NULL                                         AS UpVotes,
            NULL                                         AS DownVotes,
            NULL                                         AS LastActivityTimestamp,
            h.RankByReputation                           AS Rank,
            'HighAcceptNoGold'                           AS Category
    FROM    HighAcceptanceNonGold h
) AS BenchmarkResults
ORDER BY Category, Rank
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
