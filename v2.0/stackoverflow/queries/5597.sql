-- {"query": "5597.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1271}
WITH qualifying_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
recent_activity AS (
  SELECT
    qp.PostId,
    qp.Title,
    qp.CreationDate,
    qp.LastActivityDate,
    qp.OwnerUserId,
    qp.Score,
    qp.ViewCount,
    qp.AnswerCount,
    qp.CommentCount,
    qp.FavoriteCount,
    qp.Tags,
    vp.VoteCount,
    vp.UpVotes,
    vp.DownVotes
  FROM qualifying_posts qp
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS VoteCount,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) vp ON vp.PostId = qp.PostId
),
mixed_metrics AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ra.Score,
    ra.ViewCount,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.Tags,
    ra.VoteCount,
    ra.UpVotes AS PostUpVotes,
    ra.DownVotes AS PostDownVotes,
    COUNT(*) OVER (PARTITION BY ra.OwnerUserId) AS PostsByOwner,
    MAX(ra.LastActivityDate) OVER (PARTITION BY ra.OwnerUserId) AS LastActiveForOwner,
    (SELECT STRING_AGG(distinct CAST(vp2.VoteCount AS VARCHAR), ',') FROM (
        SELECT VoteCount
        FROM (
          SELECT PostId, COUNT(*) AS VoteCount
          FROM Votes
          GROUP BY PostId
        ) AS vcounts
      ) vp2
    ) AS AllVoteCounts
  FROM recent_activity ra
  LEFT JOIN Users u ON u.Id = ra.OwnerUserId
),
correlated_subq AS (
  SELECT
    mm.PostId,
    mm.Title,
    mm.CreationDate,
    mm.LastActivityDate,
    mm.OwnerUserId,
    mm.Reputation,
    mm.OwnerDisplayName,
    mm.Location,
    mm.AccountId,
    mm.Views,
    mm.UpVotes AS OwnerUpVotes,
    mm.DownVotes AS OwnerDownVotes,
    mm.Score,
    mm.ViewCount,
    mm.AnswerCount,
    mm.CommentCount,
    mm.FavoriteCount,
    mm.Tags,
    mm.VoteCount,
    mm.PostUpVotes,
    mm.PostDownVotes,
    CASE
      WHEN mm.Reputation IS NULL THEN NULL
      ELSE mm.Reputation * 0.5 + mm.PostUpVotes * 2 - mm.PostDownVotes
    END AS ScoreComposite
  FROM mixed_metrics mm
),
windowed AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.CreationDate,
    cs.LastActivityDate,
    cs.OwnerUserId,
    cs.Reputation,
    cs.OwnerDisplayName,
    cs.Location,
    cs.AccountId,
    cs.Views,
    cs.Views AS ViewCountAlias,
    cs.Score,
    cs.ViewCount,
    cs.AnswerCount,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.Tags,
    cs.VoteCount,
    cs.OwnerUpVotes,
    cs.OwnerDownVotes,
    cs.PostUpVotes,
    cs.PostDownVotes,
    cs.ScoreComposite,
    ROW_NUMBER() OVER (
      PARTITION BY cs.OwnerUserId
      ORDER BY cs.ScoreComposite DESC, cs.LastActivityDate DESC
    ) AS rn_by_owner
  FROM correlated_subq cs
),
final AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.LastActivityDate,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.Location,
    w.AccountId,
    w.Views,
    w.Score,
    w.ViewCount,
    w.AnswerCount,
    w.CommentCount,
    w.FavoriteCount,
    w.Tags,
    w.VoteCount,
    w.OwnerUpVotes,
    w.OwnerDownVotes,
    w.PostUpVotes,
    w.PostDownVotes,
    w.ScoreComposite,
    w.rn_by_owner
  FROM windowed w
  WHERE w.rn_by_owner = 1
),
most_active_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AccountId,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(b.CountBadges, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS CountBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
hypothetical_stats AS (
  SELECT
    mau.UserId,
    mau.DisplayName,
    mau.Reputation,
    mau.Location,
    mau.AccountId,
    mnk.PostId,
    mnk.Title,
    mnk.LastActivityDate,
    mnk.ScoreComposite,
    mnk.Tags
  FROM most_active_users mau
  JOIN final mnk ON mnk.OwnerUserId = mau.UserId
)
SELECT
  hs.UserId,
  hs.DisplayName AS Owner,
  hs.Location,
  hs.AccountId,
  hs.PostId,
  hs.Title,
  hs.LastActivityDate,
  hs.ScoreComposite,
  hs.Tags
FROM hypothetical_stats hs
ORDER BY hs.ScoreComposite DESC
LIMIT 100;