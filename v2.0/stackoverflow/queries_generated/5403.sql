-- {"query": "5403.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 711} 
WITH hot_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate IS NOT NULL
    AND p.Views IS NULL OR p.ViewCount >= 0
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes
  FROM Users u
),
recent_bounties AS (
  SELECT
    v.PostId,
    v.UserId AS BountyUserId,
    v.BountyAmount,
    v.CreationDate AS BountyDate
  FROM Votes v
  WHERE v.VoteTypeId = 8 -- BountyStart
),
tag_alias AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
)
SELECT
  hp.PostId,
  hp.Title AS QuestionTitle,
  hp.LastActivityDate,
  hp.Score AS QuestionScore,
  hp.ViewCount AS Views,
  hp.Tags,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  ro.Name AS CloseReason,
  json_build_object(
    'TopVoters', (
      SELECT json_agg(json_build_object('User', VotesUser.DisplayName, 'Score', v.Score, 'Date', v.CreationDate))
      FROM Votes v
      JOIN Users VotesUser ON v.UserId = VotesUser.Id
      WHERE v.PostId = hp.PostId
        AND v.VoteTypeId = 2
      ORDER BY v.CreationDate DESC
      LIMIT 5
    ),
    'Tags', (SELECT string_agg(t.TagName, ',')
             FROM string_to_array(substring(hp.Tags from 2 for char_length(hp.Tags)-2), '><') AS ta(t)
             LEFT JOIN tag_alias t ON t.TagName = ta.t
             )
  ) AS Meta,
  (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = hp.PostId AND vv.VoteTypeId = 2) AS UpVotesCount,
  (SELECT Count(*) FROM Comments c WHERE c.PostId = hp.PostId) AS CommentCount
FROM hot_posts hp
JOIN top_users u ON hp.OwnerUserId = u.UserId
LEFT JOIN PostLinks pl ON pl.PostId = hp.PostId
LEFT JOIN Posts pr ON pr.Id = pl.RelatedPostId
LEFT JOIN PostHistory ph ON ph.PostId = hp.PostId
LEFT JOIN CloseReasonTypes ro ON ro.Id = (SELECT CAST(ph.Comment AS int) 
                                        FROM PostHistory ph2
                                        WHERE ph2.PostId = hp.PostId AND ph2.PostHistoryTypeId = 10
                                        ORDER BY ph2.CreationDate DESC LIMIT 1)
WHERE hp.rn <= 100
ORDER BY hp.LastActivityDate DESC, hp.Score DESC
LIMIT 100;