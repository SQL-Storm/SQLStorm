-- {"query": "5584.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 892}
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId,
    pv.MaxVoteDate,
    pv.MaxVoteUserId
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      MAX(CreationDate) AS MaxVoteDate,
      MAX(CASE WHEN VoteTypeId = 2 THEN UserId END) AS MaxVoteUserId
    FROM Votes
    GROUP BY PostId
  ) pv ON pv.PostId = p.Id
  WHERE p.PostTypeId = 1
),
closed AS (
  SELECT
    t.PostId,
    t.Comment AS ClosureComment,
    t.CreationDate AS ClosureDate,
    crt.Name AS ClosureReason
  FROM PostHistory t
  LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(
    CASE
      WHEN t.Comment LIKE '%CloseReason%' THEN JSON_VALUE(t.Comment, '$.reason')
      ELSE t.Comment
    END AS SMALLINT)
  WHERE t.PostId IS NOT NULL
    AND t.PostHistoryTypeId = 10
),
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AccountId,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
  FROM Users u
),
exploded_tags AS (
  SELECT
    t.PostId,
    v.tag AS TagName
  FROM top_questions t
  CROSS JOIN LATERAL (
    SELECT UNNEST(string_to_array(SUBSTRING(t.Tags FROM 2 FOR (CHAR_LENGTH(t.Tags)-2)), '><')) AS tag
  ) v
)
SELECT
  t.PostId,
  t.Title,
  t.CreationDate AS PostCreationDate,
  t.ViewCount,
  t.Score,
  t.AnswerCount,
  t.CommentCount,
  t.FavoriteCount,
  t.LastActivityDate,
  t.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  u.WebsiteUrl,
  u.AccountId,
  COALESCE(cl.ClosureDate, NULL) AS ClosedDate,
  cl.ClosureComment,
  cl.ClosureReason,
  ut.GoldBadges,
  ut.SilverBadges,
  ut.BronzeBadges,
  et.TagName,
  RANK() OVER (PARTITION BY et.TagName ORDER BY t.Score DESC, t.ViewCount DESC) AS ScoreRank,
  CASE
    WHEN t.Score > 10 AND t.ViewCount > 1000 THEN TRUE
    ELSE FALSE
  END AS HighEngagement,
  v.MaxVoteDate,
  v.MaxReopenDate
FROM top_questions t
LEFT JOIN user_stats ut ON ut.UserId = t.OwnerUserId
LEFT JOIN user_stats u ON u.UserId = t.OwnerUserId
LEFT JOIN closed cl ON cl.PostId = t.PostId
LEFT JOIN exploded_tags et ON et.PostId = t.PostId
LEFT JOIN (
  SELECT
    PostId,
    MAX(CASE WHEN VoteTypeId = 2 THEN CreationDate END) AS MaxVoteDate,
    MAX(CASE WHEN VoteTypeId = 7 THEN CreationDate END) AS MaxReopenDate
  FROM Votes
  GROUP BY PostId
) v ON v.PostId = t.PostId
GROUP BY
  t.PostId,
  t.Title,
  t.CreationDate,
  t.ViewCount,
  t.Score,
  t.AnswerCount,
  t.CommentCount,
  t.FavoriteCount,
  t.LastActivityDate,
  t.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.WebsiteUrl,
  u.AccountId,
  cl.ClosureDate,
  cl.ClosureComment,
  cl.ClosureReason,
  ut.GoldBadges,
  ut.SilverBadges,
  ut.BronzeBadges,
  et.TagName,
  v.MaxVoteDate,
  v.MaxReopenDate
ORDER BY t.Score DESC, t.LastActivityDate DESC
LIMIT 100;