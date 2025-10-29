-- {"query": "3730.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2689} 

WITH
    -- Aggregate per‑user statistics
    UserStats AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(COALESCE(p.Score,0))               AS TotalScore,
            MAX(p.CreationDate)                    AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    -- Badge aggregates and a ranking window
    BadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(*)                                           AS BadgeCount,
            SUM(CASE b.Class WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 1 END) AS BadgeWeight,
            ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- Top tags overall (used only for a STRING_AGG example)
    TopTags AS (
        SELECT
            t.TagName,
            t.Count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    ),

    -- Most recent vote activity per post
    RecentVotes AS (
        SELECT
            v.PostId,
            MAX(v.CreationDate)                     AS LastVoteDate,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
        FROM Votes v
        GROUP BY v.PostId
    )

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    ba.BadgeCount,
    ba.BadgeWeight,
    COALESCE(rv.UpVotes,0)   AS RecentUpVotes,
    COALESCE(rv.DownVotes,0) AS RecentDownVotes,
    CASE
        WHEN us.TotalScore > 0 THEN 'Positive'
        WHEN us.TotalScore < 0 THEN 'Negative'
        ELSE 'Neutral'
    END                     AS ScoreSign,
    /* aggregate the five most frequent tags used by the user */
    STRING_AGG(DISTINCT tt.TagName, ', ') FILTER (WHERE tt.rn <= 5) AS Top5Tags,
    /* correlated subquery: latest accepted answer title for the user's most recent question */
    (
        SELECT p.Title
        FROM Posts p
        WHERE p.PostTypeId = 2                -- answer
          AND p.ParentId = q.Id
          AND p.Id = q.AcceptedAnswerId
        ORDER BY p.CreationDate DESC
        LIMIT 1
    ) AS LatestAcceptedAnswerTitle,
    /* left join – may be null */
    c.Text AS LatestCommentText,
    /* set‑operator style flag */
    CASE WHEN us.Reputation >= 1000 OR ba.BadgeWeight >= 15 THEN 1 ELSE 0 END AS IsPowerUser,
    COALESCE(us.LastPostDate, TIMESTAMP '1970-01-01') AS LastActivity
FROM UserStats us
LEFT JOIN BadgeAgg ba ON ba.UserId = us.UserId
/* most recent post of the user – used to fetch its vote stats */
LEFT JOIN LATERAL (
    SELECT rv.UpVotes, rv.DownVotes
    FROM RecentVotes rv
    WHERE rv.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = us.UserId
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
) rv ON TRUE
/* latest comment made by the user (may be null) */
LEFT JOIN LATERAL (
    SELECT cm.Text
    FROM Comments cm
    WHERE cm.UserId = us.UserId
    ORDER BY cm.CreationDate DESC
    LIMIT 1
) c ON TRUE
/* explode tags of the user's questions and rank them */
LEFT JOIN LATERAL (
    SELECT
        t.TagName,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM (
        SELECT UNNEST(string_to_array(p.Tags, '><')) AS Tag
        FROM Posts p
        WHERE p.OwnerUserId = us.UserId
          AND p.PostTypeId = 1               -- question
    ) pt
    JOIN Tags t ON t.TagName = pt.Tag
) tt ON TRUE
/* most recent question of the user for the correlated subquery above */
LEFT JOIN LATERAL (
    SELECT q.Id
    FROM Posts q
    WHERE q.OwnerUserId = us.UserId
      AND q.PostTypeId = 1
    ORDER BY q.CreationDate DESC
    LIMIT 1
) q ON TRUE
WHERE us.Reputation IS NOT NULL

UNION ALL

/* aggregate row for all users – demonstrates a set operator */
SELECT
    -1                                    AS UserId,
    'Aggregate'                           AS DisplayName,
    SUM(us.Reputation)                    AS Reputation,
    SUM(us.QuestionCount)                 AS QuestionCount,
    SUM(us.AnswerCount)                   AS AnswerCount,
    SUM(us.TotalScore)                    AS TotalScore,
    SUM(ba.BadgeCount)                    AS BadgeCount,
    SUM(ba.BadgeWeight)                   AS BadgeWeight,
    SUM(COALESCE(rv.UpVotes,0))           AS RecentUpVotes,
    SUM(COALESCE(rv.DownVotes,0))         AS RecentDownVotes,
    'Mixed'                               AS ScoreSign,
    NULL                                  AS Top5Tags,
    NULL                                  AS LatestAcceptedAnswerTitle,
    NULL                                  AS LatestCommentText,
    0                                     AS IsPowerUser,
    NULL                                  AS LastActivity
FROM UserStats us
LEFT JOIN BadgeAgg ba ON ba.UserId = us.UserId
LEFT JOIN LATERAL (
    SELECT rv.UpVotes, rv.DownVotes
    FROM RecentVotes rv
    WHERE rv.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = us.UserId
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
) rv ON TRUE
HAVING COUNT(*) > 0

ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
