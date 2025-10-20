WITH recent_posts AS (
    SELECT
        p.Id         AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        REGEXP_REPLACE(t.tag, '^<|>$', '', 'g') AS TagName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, REGEXP_REPLACE(t.tag, '^<|>$', '', 'g') ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p,
    LATERAL (SELECT unnest(regexp_split_to_array(p.Tags, '><')) AS tag) t
    WHERE p.PostTypeId = 1
),
top_voter AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        RANK() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rank
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
),
user_stats AS (
    SELECT
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        SUM(p.Score) AS total_score,
        COUNT(c.Id) AS comment_count,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.LastAccessDate
),
closed_questions AS (
    SELECT
        p.Id,
        ph.UserDisplayName AS closer,
        COALESCE(ct.Name, 'Unknown') AS close_reason
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes ct ON CAST(ph.Comment AS INTEGER) = ct.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
),
recent_metrics AS (
    SELECT
        rp.OwnerUserId,
        rp.TagName,
        COUNT(rp.PostId) OVER (PARTITION BY rp.OwnerUserId, rp.TagName)        AS total_tag_posts,
        AVG(rp.Score)  OVER (PARTITION BY rp.OwnerUserId, rp.TagName)         AS avg_tag_score,
        MAX(rp.CreationDate) OVER (PARTITION BY rp.OwnerUserId)              AS latest_user_post
    FROM recent_posts rp
    WHERE rp.rn = 1
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.question_count,
    us.answer_count,
    us.total_score,
    us.comment_count,
    us.gold_badges,
    rm.total_tag_posts,
    rm.avg_tag_score,
    rm.latest_user_post,
    COALESCE(cc.closer, 'N/A')     AS last_closer,
    COALESCE(cc.close_reason, 'N/A') AS last_close_reason
FROM user_stats us
LEFT JOIN recent_metrics rm ON rm.OwnerUserId = us.Id
LEFT JOIN closed_questions cc ON cc.Id = (
    SELECT p2.Id
    FROM Posts p2
    WHERE p2.OwnerUserId = us.Id
      AND p2.PostTypeId = 1
    ORDER BY p2.ClosedDate DESC
    LIMIT 1
)
WHERE us.Reputation > 0
  AND (us.total_score IS NULL OR us.total_score > 0)
  AND EXISTS (
        SELECT 1
        FROM Votes vv
        WHERE vv.PostId IN (
                SELECT p3.Id
                FROM Posts p3
                WHERE p3.OwnerUserId = us.Id
              )
          AND vv.VoteTypeId = 2
          AND vv.CreationDate > (us.LastAccessDate - INTERVAL '30' DAY)
  )
UNION ALL
SELECT
    NULL,
    'Aggregate',
    NULL,
    SUM(question_count),
    SUM(answer_count),
    SUM(total_score),
    SUM(comment_count),
    SUM(gold_badges),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM user_stats;