-- {"query": "3372.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2264} 

/*  PERFORMANCE BENCHMARK QUERY – uses CTEs, window functions, outer joins,
    correlated subqueries, set operators, string manipulation and NULL logic   */
WITH
/* ----------------------------------------------------------------------
   Aggregate per‑user basic activity
   ---------------------------------------------------------------------- */
UserStats AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)               AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)               AS AnswerCount,
        COALESCE(SUM(p.Score),0)                               AS TotalScore,
        MAX(p.CreationDate)                                   AS LastPostDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)     AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)     AS DownVotesGiven,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* ----------------------------------------------------------------------
   Global most‑used tags (derived from questions)
   ---------------------------------------------------------------------- */
TopTags AS (
    SELECT
        t.TagName,
        COUNT(*)                                           AS TagUseCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)        AS rn
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS tag_raw(tag)
    JOIN Tags t ON t.TagName = tag_raw.tag
    WHERE p.PostTypeId = 1               -- only questions
    GROUP BY t.TagName
),

/* ----------------------------------------------------------------------
   Per‑user tag score (sum of question scores per tag)
   ---------------------------------------------------------------------- */
UserTagScore AS (
    SELECT
        u.Id                                   AS UserId,
        t.TagName,
        SUM(p.Score)                           AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id
                           ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS tag_raw(tag)
    JOIN Tags t ON t.TagName = tag_raw.tag
    GROUP BY u.Id, t.TagName
),

/* ----------------------------------------------------------------------
   Most recent closed question per user (including close reason)
   ---------------------------------------------------------------------- */
RecentClosed AS (
    SELECT
        p.Id                                   AS PostId,
        p.OwnerUserId,
        p.Title,
        ph.CreationDate                        AS ClosedDate,
        COALESCE(NULLIF(ph.Comment, ''), 'No reason supplied') AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph
      ON ph.PostId = p.Id
     AND ph.PostHistoryTypeId = 10               -- Post Closed
    WHERE p.ClosedDate IS NOT NULL
)

/* ----------------------------------------------------------------------
   Final result set – combines all pieces, applies filters,
   adds derived columns, and demonstrates UNION ALL as a set operator.
   ---------------------------------------------------------------------- */
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    us.LastPostDate,
    (us.UpVotesGiven - us.DownVotesGiven)                     AS NetVotesGiven,
    us.BadgeCount,
    tt.TagName                 AS GlobalTopTag,
    tt.TagUseCount,
    uts.TagName                AS UserTopTag,
    uts.TagScore,
    rc.Title                   AS RecentClosedTitle,
    rc.CloseReason,
    CASE
        WHEN us.Reputation >= 20000 THEN 'Veteran'
        WHEN us.Reputation BETWEEN 10000 AND 19999 THEN 'Experienced'
        WHEN us.Reputation BETWEEN 5000  AND 9999  THEN 'Intermediate'
        ELSE 'Newbie'
    END                         AS ReputationBand,
    /* Correlated scalar sub‑query: total comments on user's questions */
    (SELECT COUNT(*)
       FROM Comments c
      WHERE c.PostId IN (SELECT p2.Id
                           FROM Posts p2
                          WHERE p2.OwnerUserId = us.UserId
                            AND p2.PostTypeId = 1))       AS QuestionCommentCount
FROM UserStats      us
LEFT JOIN TopTags   tt  ON tt.rn = 1                                 -- global #1 tag
LEFT JOIN UserTagScore uts ON uts.UserId = us.UserId AND uts.TagRank = 1
LEFT JOIN RecentClosed rc  ON rc.OwnerUserId = us.UserId AND rc.rn = 1
WHERE us.QuestionCount > 0
  AND (us.TotalScore IS NULL OR us.TotalScore <> 0)
ORDER BY us.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY

UNION ALL

/* Dummy row to force a UNION ALL plan node – never returns rows */
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
WHERE FALSE;
