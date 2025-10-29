-- {"query": "3131.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1622}
WITH QuestionStats AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2)                AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)          AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)          AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Posts a      ON a.ParentId = p.Id
    LEFT JOIN Votes v      ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId
),
TagAgg AS (
    SELECT
        pt.Id                                   AS PostId,
        STRING_AGG(t.TagName, ',')              AS TagList,
        COUNT(*) FILTER (WHERE t.IsModeratorOnly = TRUE) AS ModTagCount
    FROM Posts pt
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(trim(both '<>' FROM pt.Tags), '><') AS tag
    ) AS tagsplit
    JOIN Tags t ON t.TagName = tagsplit.tag
    GROUP BY pt.Id
),
BadgeScore AS (
    SELECT
        u.Id                                   AS UserId,
        COALESCE(SUM(
            CASE b.Class
                WHEN 1 THEN 1000
                WHEN 2 THEN 500
                ELSE 100
            END
        ),0)                                   AS BadgePoints
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    qs.Id                                    AS QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.AnswerCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.rn,
    COALESCE(ta.TagList, '')                 AS Tags,
    ta.ModTagCount,
    COALESCE(bs.BadgePoints,0)               AS UserBadgePoints,
    u.Reputation,
    (qs.UpVotes - qs.DownVotes) * LOG(1 + u.Reputation) AS ScoreWeight,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostHistory ph
            WHERE ph.PostId = qs.Id
              AND ph.PostHistoryTypeId = 10
              AND (CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER) ELSE NULL END) = 101
        ) THEN 'DuplicateClose'
        ELSE 'Open'
    END                                      AS CloseReasonFlag,
    (SELECT MAX(v.CreationDate)
     FROM Votes v
     WHERE v.PostId = qs.Id AND v.VoteTypeId = 2) AS LastUpvoteDate,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.PostId = qs.Id AND c.Score > 0) AS PositiveCommentCount,
    (SELECT b.Name
     FROM Badges b
     WHERE b.UserId = qs.OwnerUserId
     ORDER BY b.Date DESC
     LIMIT 1)                                 AS LatestBadgeName
FROM QuestionStats qs
LEFT JOIN TagAgg ta      ON ta.PostId = qs.Id
LEFT JOIN BadgeScore bs  ON bs.UserId = qs.OwnerUserId
LEFT JOIN Users u        ON u.Id = qs.OwnerUserId
WHERE qs.rn = 1
  AND (qs.AnswerCount = 0 OR qs.UpVotes > qs.DownVotes)
ORDER BY ScoreWeight DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;