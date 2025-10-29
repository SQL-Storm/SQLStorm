WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
q_with_stats AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    COALESCE(v.UpVotes, 0) AS UpVotesFromVotes,
    COALESCE(v.DownVotes, 0) AS DownVotesFromVotes
  FROM recent_questions rq
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY OwnerUserId
  ) b ON rq.OwnerUserId = b.OwnerUserId
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    WHERE PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
    GROUP BY PostId
  ) v ON rq.PostId = v.PostId
),
top_posts AS (
  SELECT
    pws.PostId,
    pws.Title,
    pws.Tags,
    pws.CreationDate,
    pws.Score,
    pws.ViewCount,
    pws.OwnerUserId,
    pws.LastActivityDate,
    pws.CommentCount,
    pws.AnswerCount,
    pws.FavoriteCount,
    pws.Reputation,
    pws.OwnerDisplayName,
    pws.BadgeCount,
    pws.UpVotesFromVotes,
    pws.DownVotesFromVotes,
    ROW_NUMBER() OVER (
      PARTITION BY DATE_TRUNC('day', pws.CreationDate)
      ORDER BY pws.Score DESC, pws.ViewCount DESC, pws.LastActivityDate DESC
    ) AS rn_per_day
  FROM q_with_stats pws
),
filtered AS (
  SELECT *
  FROM top_posts
  WHERE rn_per_day = 1 -- best per day by score/view/activity
)
SELECT
  f.PostId,
  f.Title,
  string_agg(t.tagname, ',') AS TagList,
  f.CreationDate,
  f.Score,
  f.ViewCount,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.Reputation,
  f.BadgeCount,
  f.UpVotesFromVotes,
  f.DownVotesFromVotes,
  f.LastActivityDate,
  f.CommentCount,
  f.AnswerCount,
  f.FavoriteCount
FROM filtered f
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(REPLACE(REPLACE(f.Tags, '<', ''), '>', ''), ',')) AS tagname
) t ON TRUE
GROUP BY
  f.PostId, f.Title, f.CreationDate, f.Score, f.ViewCount, f.OwnerUserId,
  f.OwnerDisplayName, f.Reputation, f.BadgeCount, f.UpVotesFromVotes,
  f.DownVotesFromVotes, f.LastActivityDate, f.CommentCount, f.AnswerCount, f.FavoriteCount
ORDER BY f.CreationDate DESC
LIMIT 100;