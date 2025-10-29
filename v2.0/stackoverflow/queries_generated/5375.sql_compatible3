WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
top_recent_questions AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.ViewCount,
    rq.Score,
    rq.Tags,
    rq.LastActivityDate,
    rq.AnswerCount,
    rq.CommentCount,
    ROW_NUMBER() OVER (ORDER BY rq.Score DESC, rq.ViewCount DESC) AS rn
  FROM recent_questions rq
),
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
tag_popularity AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
combined AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.CreationDate,
    tq.OwnerUserId,
    tu.DisplayName AS OwnerDisplayName,
    tu.Reputation AS OwnerReputation,
    pq.ViewCount,
    pq.Score,
    pq.LastActivityDate,
    pq.AnswerCount,
    pq.CommentCount,
    STRING_AGG(tt.TagName, ',') AS TagList,
    CAST(CONCAT(
      '{',
        '"gold":', COALESCE(CAST(ub.GoldBadges AS VARCHAR), '0'), ',',
        '"silver":', COALESCE(CAST(ub.SilverBadges AS VARCHAR), '0'), ',',
        '"bronze":', COALESCE(CAST(ub.BronzeBadges AS VARCHAR), '0'),
      '}'
    ) AS JSON) AS OwnerBadgeSummary
  FROM top_recent_questions tq
  LEFT JOIN Posts pq ON pq.Id = tq.PostId
  LEFT JOIN Users tu ON tu.Id = tq.OwnerUserId
  LEFT JOIN user_stats ub ON ub.UserId = tu.Id
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(tq.Tags, '<>')) AS TagName
  ) AS tt ON TRUE
  GROUP BY
    tq.PostId, tq.Title, tq.CreationDate, tq.OwnerUserId,
    tu.DisplayName, tu.Reputation, pq.ViewCount, pq.Score,
    pq.LastActivityDate, pq.AnswerCount, pq.CommentCount,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.ViewCount,
  c.Score,
  c.LastActivityDate,
  c.AnswerCount,
  c.CommentCount,
  c.TagList,
  c.OwnerBadgeSummary,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = c.PostId) AS ChildPostCount,
  -- build arrays of user ids as JSON arrays in a dialect-agnostic way
  (SELECT CAST('[' || COALESCE(string_agg(CAST(v.UserId AS VARCHAR), ','), '') || ']' AS JSON)
   FROM Votes v
   WHERE v.PostId = c.PostId AND v.VoteTypeId = 2) AS UpvoterUserIds,
  (SELECT CAST('[' || COALESCE(string_agg(CAST(v.UserId AS VARCHAR), ','), '') || ']' AS JSON)
   FROM Votes v
   WHERE v.PostId = c.PostId AND v.VoteTypeId = 3) AS DownvoterUserIds
FROM combined c
WHERE c.Score > 0
  AND c.ViewCount >= 100
  AND (c.TagList IS NULL OR c.TagList <> '')
ORDER BY c.Score DESC, c.ViewCount DESC
LIMIT 100;