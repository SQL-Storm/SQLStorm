-- {"query": "5787.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 744}
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
),
CorrelatedStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.LastActivityDate,
    u.Reputation,
    u.DisplayName,
    COALESCE(b.CountBadges, 0) AS BadgeCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    CAST( (r.Score * 1.0) / NULLIF(r.ViewCount, 0) AS NUMERIC(10,4) ) AS ScorePerView,
    SUM(CASE WHEN vt_inner.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) OVER (PARTITION BY r.PostId) AS Accepts
  FROM RecentTopPosts r
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS CountBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = r.OwnerUserId
  LEFT JOIN (
    SELECT v2.PostId,
           SUM(CASE WHEN vt2.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt2.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v2
    JOIN VoteTypes vt2 ON vt2.Id = v2.VoteTypeId
    GROUP BY v2.PostId
  ) v ON v.PostId = r.PostId
  LEFT JOIN Votes vt_votes ON vt_votes.PostId = r.PostId
  LEFT JOIN VoteTypes vt_inner ON vt_inner.Id = vt_votes.VoteTypeId
  WHERE r.rn <= 10
),
TagBasedLinks AS (
  SELECT
    pl.PostId,
    COUNT(*) AS TagLinkCount
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId = 1 -- Linked
  GROUP BY pl.PostId
),
AllContent AS (
  SELECT
    c.*,
    COALESCE(tb.TagLinkCount, 0) AS TagLinkCount
  FROM CorrelatedStats c
  LEFT JOIN TagBasedLinks tb ON tb.PostId = c.PostId
)
SELECT
  ac.PostId,
  ac.Title,
  ac.CreationDate,
  ac.OwnerUserId,
  CASE WHEN ac.DisplayName IS NOT NULL THEN TRUE ELSE FALSE END AS HasDisplayName,
  ac.Reputation,
  ac.ViewCount,
  ac.Score,
  ac.AnswerCount,
  ac.CommentCount,
  ac.FavoriteCount,
  ac.LastActivityDate,
  ac.TagLinkCount,
  ac.BadgeCount,
  ac.UpVotes,
  ac.DownVotes,
  ac.ScorePerView,
  ac.Accepts
FROM AllContent ac
ORDER BY
  ac.Score DESC,
  ac.ViewCount DESC,
  ac.CreationDate DESC
LIMIT 100;