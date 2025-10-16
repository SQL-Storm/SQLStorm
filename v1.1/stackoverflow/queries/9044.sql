WITH
  RecentPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days'
  ),
  UserStats AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      COALESCE(
        SUM(
          CASE
            WHEN v.VoteTypeId = 2 THEN  1
            WHEN v.VoteTypeId = 3 THEN -1
            ELSE 0
          END
        ), 0
      ) AS vote_diff,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM Users u
    LEFT JOIN Votes v  ON v.UserId  = u.Id
    LEFT JOIN Badges b ON b.UserId  = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  QA_CTE AS (
    SELECT
      q.Id      AS qid,
      q.Title,
      a.Id      AS aid,
      a.Score   AS a_score,
      (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId      = a.Id
          AND c.CreationDate > q.CreationDate
      )           AS recent_comments,
      COALESCE(a.OwnerUserId, -1) AS answerer
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  ),
  MergedTags AS (
    SELECT TagName AS Name, Count FROM Tags
    UNION
    SELECT Name, COUNT(*) FROM Badges GROUP BY Name
  ),
  IntersectTagsBadges AS (
    SELECT Name, Count FROM MergedTags
    INTERSECT
    SELECT Name, COUNT(*) FROM Badges GROUP BY Name
  ),
  ExceptTagsBadges AS (
    SELECT TagName AS Name FROM Tags
    EXCEPT
    SELECT Name FROM Badges
  ),
  FlagCounts AS (
    SELECT
      ph.PostId,
      COUNT(*) AS flags
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,12,19,20)
    GROUP BY ph.PostId
  )

SELECT
  rp.Id                      AS post_id,
  rp.PostTypeId,
  COALESCE(rp.Title, '')     AS title,
  COALESCE(rp.Tags, '')      AS tags,
  us.DisplayName,
  us.Reputation,
  us.vote_diff,
  us.gold,
  us.silver,
  us.bronze,
  qc.aid,
  qc.a_score,
  qc.recent_comments,
  fc.flags,
  CASE
    WHEN rp.PostTypeId = 1
     AND EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = rp.Id)
    THEN 'HasAnswers'
    ELSE 'NoAnswers'
  END                         AS has_answers,
  (
    SELECT MAX(LENGTH(c.Text))
    FROM Comments c
    WHERE c.PostId = rp.Id
  )                           AS max_comment_len,
  DENSE_RANK() OVER (ORDER BY us.Reputation DESC) AS user_rank,
  (LENGTH(rp.Tags) - LENGTH(REPLACE(rp.Tags, '><', ''))) AS tag_count
FROM RecentPosts rp
LEFT JOIN UserStats us ON us.Id     = rp.OwnerUserId
LEFT JOIN QA_CTE    qc ON qc.qid    = rp.Id
LEFT JOIN FlagCounts fc ON fc.PostId = rp.Id
WHERE rp.rn <= 10
  AND us.vote_diff <> 0
  AND rp.Tags LIKE '%<sql>%'

UNION ALL

SELECT
  CAST(0 AS INTEGER) AS post_id,
  CAST(0 AS INTEGER) AS PostTypeId,
  CAST(NULL AS TEXT) AS title,
  CAST(NULL AS TEXT) AS tags,
  CAST(NULL AS TEXT) AS DisplayName,
  CAST(0 AS INTEGER) AS Reputation,
  CAST(0 AS INTEGER) AS vote_diff,
  CAST(0 AS INTEGER) AS gold,
  CAST(0 AS INTEGER) AS silver,
  CAST(0 AS INTEGER) AS bronze,
  CAST(NULL AS INTEGER) AS aid,
  CAST(0 AS INTEGER) AS a_score,
  CAST(0 AS INTEGER) AS recent_comments,
  CAST(0 AS INTEGER) AS flags,
  CAST('None' AS TEXT) AS has_answers,
  CAST(0 AS INTEGER) AS max_comment_len,
  CAST(0 AS INTEGER) AS user_rank,
  CAST(0 AS INTEGER) AS tag_count
FROM ExceptTagsBadges etb

LIMIT 50;