-- {"query": "5617.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 910}
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
),
recent_activities AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS HistoryDate,
    ph.PostHistoryTypeId,
    ph.UserId AS HistoryUserId,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
),
user_summary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.WebsiteUrl,
    u.ProfileImageUrl,
    COUNT(DISTINCT t.Id) AS TagCount,
    MAX(p.LastActivityDate) AS LastActiveQuestionDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Tags t ON POSITION(CONCAT('<', t.TagName, '>') IN COALESCE(p.Tags, '')) > 0
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.AccountId, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.WebsiteUrl,
    u.ProfileImageUrl
),
complex_metric AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.Tags,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.LastActivityDate,
    tp.AnswerCount,
    tp.CommentCount,
    tp.FavoriteCount,
    tp.ContentLicense,
    COALESCE(v_up.VoteCount, 0) AS UpVotesGiven,
    COALESCE(v_down.VoteCount, 0) AS DownVotesGiven,
    COALESCE(bg.GoldCount, 0) AS GoldBadgesForOwner,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN tp.LastActivityDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7 days' THEN 'Active'
      ELSE 'Dormant'
    END AS ActivityLabel
  FROM top_questions tp
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) v_up ON v_up.PostId = tp.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) v_down ON v_down.PostId = tp.PostId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldCount
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) bg ON bg.UserId = tp.OwnerUserId
  LEFT JOIN Posts p ON p.Id = tp.PostId
  WHERE tp.Score > 0
    AND tp.ViewCount >= 50
),
final AS (
  SELECT
    cm.PostId,
    cm.Title,
    cm.Tags,
    cm.CreationDate,
    cm.Score,
    cm.ViewCount,
    cm.OwnerUserId,
    cm.LastActivityDate,
    cm.AnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.ContentLicense,
    cm.UpVotesGiven,
    cm.DownVotesGiven,
    cm.GoldBadgesForOwner,
    cm.ActivityLabel,
    ru.DisplayName AS OwnerDisplayName,
    ru.Reputation AS OwnerReputation,
    ru.LastAccessDate AS OwnerLastAccess
  FROM complex_metric cm
  LEFT JOIN Users ru ON ru.Id = cm.OwnerUserId
)
SELECT
  *
FROM final
WHERE ActivityLabel <> 'Dormant'
ORDER BY Score DESC, ViewCount DESC
LIMIT 200;