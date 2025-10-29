-- {"query": "3274.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2269} 

/*  Benchmarking query:  a heavyweight report that blends CTEs, window functions,
    outer joins, correlated sub‑queries, set operators, string math and NULL handling   */

WITH
/* -------------------------------------------------------------------------
   1️⃣  Gather per‑user post statistics (questions, answers, score, tag density)
   ------------------------------------------------------------------------- */
UserPostStats AS (
    SELECT
        u.Id                                     AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)          AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)          AS AnswerCount,
        SUM(COALESCE(p.Score,0))                             AS TotalScore,
        MAX(p.CreationDate)                                 AS LastPostDate,
        /*  Approximate number of tags per post (tags are stored like "<c#><sql>")  */
        AVG(
            CASE
                WHEN p.Tags IS NOT NULL AND p.Tags <> ''
                     THEN (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags,'><',''))) / 2 + 1
                ELSE 0
            END
        )                                                   AS AvgTagCount
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

/* -------------------------------------------------------------------------
   2️⃣  Badge aggregation per user (counts, gold specifics, latest badge date)
   ------------------------------------------------------------------------- */
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*)                                          AS BadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 1)               AS GoldBadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames,
        MAX(b.Date)                                       AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

/* -------------------------------------------------------------------------
   3️⃣  Votes received on a user’s posts (up / down) – uses a correlated sub‑query
   ------------------------------------------------------------------------- */
UserVoteStats AS (
    SELECT
        p.OwnerUserId                                    AS UserId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)       AS UpVotesReceived,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)       AS DownVotesReceived
    FROM Votes v
    JOIN Posts p          ON p.Id = v.PostId
    JOIN VoteTypes vt     ON vt.Id = v.VoteTypeId
    GROUP BY p.OwnerUserId
),

/* -------------------------------------------------------------------------
   4️⃣  Combine the three previous CTEs – window function supplies rank by score
   ------------------------------------------------------------------------- */
UserAggregated AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        COALESCE(ups.QuestionCount,0)          AS QuestionCount,
        COALESCE(ups.AnswerCount,0)            AS AnswerCount,
        COALESCE(ups.TotalScore,0)             AS TotalScore,
        COALESCE(ups.AvgTagCount,0)            AS AvgTagCount,
        COALESCE(ubs.BadgeCount,0)             AS BadgeCount,
        COALESCE(ubs.GoldBadgeCount,0)         AS GoldBadgeCount,
        uvs.GoldBadgeNames,
        COALESCE(uvs.UpVotesReceived,0)        AS UpVotesReceived,
        COALESCE(uvs.DownVotesReceived,0)      AS DownVotesReceived,
        ups.LastPostDate,
        ubs.LastBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY ups.UserId ORDER BY ups.TotalScore DESC) AS RankByScore
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs
           ON ubs.UserId = ups.UserId
    LEFT JOIN (
        SELECT
            uv.UserId,
            SUM(uv.UpVotesReceived)    AS UpVotesReceived,
            SUM(uv.DownVotesReceived)  AS DownVotesReceived,
            MAX(b.GoldBadgeNames)      AS GoldBadgeNames
        FROM UserVoteStats uv
        LEFT JOIN UserBadgeStats b
               ON b.UserId = uv.UserId
        GROUP BY uv.UserId
    ) uvs
           ON uvs.UserId = ups.UserId
)

/* -------------------------------------------------------------------------
   5️⃣  Final result set:
       – Top‑100 active users (by score) plus a UNION with high‑rep users who have never posted
   ------------------------------------------------------------------------- */
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.AvgTagCount,
    ua.BadgeCount,
    ua.GoldBadgeCount,
    ua.GoldBadgeNames,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.LastPostDate,
    ua.LastBadgeDate,
    ua.RankByScore
FROM UserAggregated ua
WHERE ua.RankByScore <= 100
  AND (ua.QuestionCount > 0 OR ua.AnswerCount > 0)

UNION ALL

SELECT
    u.Id                                 AS UserId,
    u.DisplayName,
    0                                    AS QuestionCount,
    0                                    AS AnswerCount,
    0                                    AS TotalScore,
    0                                    AS AvgTagCount,
    0                                    AS BadgeCount,
    0                                    AS GoldBadgeCount,
    NULL                                 AS GoldBadgeNames,
    0                                    AS UpVotesReceived,
    0                                    AS DownVotesReceived,
    NULL                                 AS LastPostDate,
    NULL                                 AS LastBadgeDate,
    NULL                                 AS RankByScore
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation > 1000
ORDER BY TotalScore DESC NULLS LAST, GoldBadgeCount DESC;
