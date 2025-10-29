WITH RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
UserReps AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE((
            SELECT SUM(p.Score)
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
              AND p.PostTypeId = 1
        ), 0) AS QuestionScoreSum,
        (
            SELECT COUNT(*)
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
              AND p.PostTypeId = 1
        ) AS QuestionCount,
        (
            SELECT COUNT(DISTINCT v.PostId)
            FROM Votes v
            WHERE v.UserId = u.Id
              AND v.VoteTypeId = 2
        ) AS UpVoteGivenCount
    FROM Users u
    WHERE u.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionWithTag,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Tags t
    JOIN Posts p
        ON p.Tags LIKE ('%<' || t.TagName || '>%')
    LEFT JOIN Votes v
        ON v.PostId = p.Id
    GROUP BY t.TagName
),
UserTopQuestions AS (
    SELECT
        rp.OwnerUserId,
        rp.Id AS PostId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.Tags,
        (rp.Score * 1.0) / NULLIF(rp.ViewCount, 0) AS ScorePerView,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = rp.Id
        ) AS CommentCount,
        (
            SELECT STRING_AGG(pht.Name, ',')
            FROM PostHistory ph
            JOIN PostHistoryTypes pht
                ON pht.Id = ph.PostHistoryTypeId
            WHERE ph.PostId = rp.Id
              AND ph.PostHistoryTypeId IN (4,5,6)
            GROUP BY ph.PostId
            ORDER BY MAX(ph.CreationDate) DESC
            LIMIT 5
        ) AS RecentEdits
    FROM RecentPosts rp
    WHERE rp.rn = 1
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.QuestionScoreSum,
    utq.Title,
    utq.Score,
    utq.ViewCount,
    ROUND(utq.ScorePerView, 4) AS ScorePerView,
    utq.CommentCount,
    utq.RecentEdits,
    COALESCE(ts.AvgScore, 0)      AS TagAvgScore,
    COALESCE(ts.UpVotes, 0)       AS TagUpVotes,
    COALESCE(ts.DownVotes, 0)     AS TagDownVotes
FROM UserReps u
LEFT JOIN UserTopQuestions utq
    ON utq.OwnerUserId = u.UserId
LEFT JOIN LATERAL (
    SELECT ts.TagName, ts.QuestionWithTag, ts.AvgScore, ts.UpVotes, ts.DownVotes
    FROM TagStats ts
    WHERE POSITION('<' || ts.TagName || '>' IN COALESCE(utq.Tags, '')) > 0
    ORDER BY ts.AvgScore DESC
    LIMIT 1
) ts ON TRUE
WHERE u.Reputation > 1000

UNION ALL

SELECT
    u2.Id               AS UserId,
    u2.DisplayName,
    u2.Reputation,
    0                   AS QuestionCount,
    0                   AS QuestionScoreSum,
    NULL                AS Title,
    NULL                AS Score,
    NULL                AS ViewCount,
    NULL                AS ScorePerView,
    NULL                AS CommentCount,
    NULL                AS RecentEdits,
    NULL                AS TagAvgScore,
    NULL                AS TagUpVotes,
    NULL                AS TagDownVotes
FROM Users u2
WHERE NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u2.Id
          AND p.PostTypeId = 1
    )
  AND u2.Reputation BETWEEN 500 AND 2000

ORDER BY Reputation DESC, QuestionScoreSum DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;