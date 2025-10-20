-- {"query": "12.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 827} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Views, 0) AS Views,
    COALESCE(u.UpVotes, 0) AS UpVotes,
    COALESCE(u.DownVotes, 0) AS DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.AboutMe,
    CAST(COALESCE(vs.TotalBounties, 0) AS BIGINT) AS TotalBounties,
    CAST(COALESCE(bp.PostCount, 0) AS INT) AS PostCountByOwner
  FROM Users u
  LEFT JOIN (
    -- total bounty amount given by the user
    SELECT UserId, SUM(BountyAmount) AS TotalBounties
    FROM Votes
    WHERE VoteTypeId = 8 -- BountyStart
    GROUP BY UserId
  ) vs ON vs.UserId = u.Id
  LEFT JOIN (
    -- number of posts created by user
    SELECT OwnerUserId AS UserId, COUNT(*) AS PostCount
    FROM Posts
    GROUP BY OwnerUserId
  ) bp ON bp.UserId = u.Id
),
hot_questions AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate > CURRENT_DATE - INTERVAL '180' DAY
    AND p.ViewCount > 100
),
aggregated_post_history AS (
  SELECT
    ph.PostId,
    MAX(CASE WHEN pht.Name = 'Post Closed' THEN ph.CreationDate END) AS LastCloseVoteDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseVoteDate2,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesCount
  FROM PostHistory ph
  JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  GROUP BY ph.PostId
),
combined AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.ViewCount,
    q.Score,
    q.Tags,
    q.LastActivityDate,
    ah.CloseVotesCount,
    ah.LastCloseVoteDate,
    a.TotalBounties,
    a.DisplayName AS OwnerDisplayName
  FROM hot_questions q
  LEFT JOIN aggregated_post_history ah ON ah.PostId = q.Id
  LEFT JOIN recent_user_activity a ON a.UserId = q.OwnerUserId
)
SELECT
  c.QuestionId,
  c.Title,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.ViewCount,
  c.Score,
  c.LastActivityDate,
  c.Tags,
  c.CloseVotesCount,
  c.LastCloseVoteDate,
  c.TotalBounties,
  c.PostCountByOwner
FROM combined c
LEFT JOIN LATERAL (
  SELECT
    pc.Id,
    pc.Title AS RelatedTitle,
    pc.PostTypeId,
    pc.OwnerUserId
  FROM Posts pc
  WHERE pc.Id <> c.QuestionId
    AND pc.OwnerUserId = c.OwnerUserId
    AND pc.LastActivityDate > c.LastActivityDate - INTERVAL '90' DAY
  ORDER BY pc.LastActivityDate DESC
  LIMIT 3
) AS recent_posts ON TRUE
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 100;