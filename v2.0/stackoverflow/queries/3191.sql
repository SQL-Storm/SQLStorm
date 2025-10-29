WITH top_tags AS (
    SELECT TagName, Count
    FROM Tags
    WHERE Count > 1000
    ORDER BY Count DESC
    LIMIT 10
),
question_stats AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.OwnerUserId,
        COALESCE(u.Reputation, 0) AS OwnerRep,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCnt,
        (SELECT
             SUM(CASE WHEN vt.VoteTypeId = 2 THEN 1
                      WHEN vt.VoteTypeId = 3 THEN -1
                      ELSE 0 END)
         FROM Votes vt
         WHERE vt.PostId = p.Id) AS NetScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
tagged_questions AS (
    SELECT
        qs.*,
        UNNEST(string_to_array(SUBSTRING(qs.Tags, 2, LENGTH(qs.Tags) - 2), '><')) AS Tag
    FROM question_stats qs
),
ranked_by_tag AS (
    SELECT
        tq.*,
        RANK() OVER (PARTITION BY tq.Tag ORDER BY tq.Score DESC) AS TagScoreRank,
        COUNT(*) OVER (PARTITION BY tq.Tag) AS TagQuestionCount
    FROM tagged_questions tq
    JOIN top_tags tt ON tt.TagName = tq.Tag
),
badge_counts AS (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
),
upvote_counts AS (
    SELECT PostId, COUNT(*) AS UpVoteCount
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
),
duplicate_close AS (
    SELECT ph.PostId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
      AND CAST(ph.Comment AS INTEGER) = 101
)
SELECT
    rb.Tag,
    rb.TagQuestionCount,
    rb.Title,
    rb.CreationDate,
    rb.OwnerRep,
    rb.CommentCnt,
    rb.NetScore,
    CASE
        WHEN rb.NetScore IS NULL THEN '0'
        WHEN rb.NetScore > 10    THEN 'Hot'
        WHEN rb.NetScore BETWEEN 1 AND 10 THEN 'Warm'
        ELSE 'Cold'
    END AS HeatLevel,
    COALESCE(bc.BadgeCount, 0) AS GoldBadgeCount,
    COALESCE(uv.UpVoteCount, 0) AS UpVoteCount,
    CASE
        WHEN dc.PostId IS NOT NULL THEN 'Duplicate'
        ELSE 'Original'
    END AS CloseReason
FROM ranked_by_tag rb
LEFT JOIN badge_counts bc      ON bc.UserId = rb.OwnerUserId
LEFT JOIN upvote_counts uv    ON uv.PostId = rb.Id
LEFT JOIN duplicate_close dc  ON dc.PostId = rb.Id
WHERE rb.TagScoreRank <= 5

UNION ALL

SELECT
    NULL                                 AS Tag,
    NULL                                 AS TagQuestionCount,
    p.Title,
    p.CreationDate,
    COALESCE(u.Reputation, 0)            AS OwnerRep,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)          AS CommentCnt,
    (SELECT
         SUM(CASE WHEN vt.VoteTypeId = 2 THEN 1
                  WHEN vt.VoteTypeId = 3 THEN -1
                  ELSE 0 END)
     FROM Votes vt
     WHERE vt.PostId = p.Id)                                      AS NetScore,
    'Other'                              AS HeatLevel,
    0                                    AS GoldBadgeCount,
    0                                    AS UpVoteCount,
    'N/A'                                AS CloseReason
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
  AND NOT EXISTS (SELECT 1 FROM ranked_by_tag rbr WHERE rbr.Id = p.Id)

ORDER BY
    Tag NULLS LAST,
    HeatLevel DESC,
    NetScore DESC
LIMIT 100;