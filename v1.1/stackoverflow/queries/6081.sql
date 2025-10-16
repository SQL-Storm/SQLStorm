WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
  GROUP BY t.TagName
  ORDER BY TagPostCount DESC
  LIMIT 50
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    u.DisplayName AS VoterName,
    u.Reputation AS VoterRep
  FROM Votes v
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY
),
HistoricalActivity AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY
),
CorrelatedStats AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    COALESCE(cc.CommentCount, 0) AS CommentCount,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes
  FROM RecentActivePosts rp
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) va ON va.PostId = rp.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) cc ON cc.PostId = rp.PostId
),
ComplexComputed AS (
  SELECT
    cs.PostId,
    cs.PostTypeId,
    cs.OwnerUserId,
    cs.Score,
    cs.ViewCount,
    cs.CommentCount,
    cs.UpVotes,
    cs.DownVotes,
    (cs.Score * 1.0 / NULLIF(cs.ViewCount, 0)) AS ScorePerView,
    (cs.UpVotes - cs.DownVotes) AS NetVotes,
    CASE
      WHEN cs.OwnerUserId IS NULL THEN 'Unknown'
      WHEN u.Location IS NULL THEN 'NoLocation'
      ELSE u.Location
    END AS OwnerLocation,
    u.Location AS OwnerLocation_raw,
    cs.Score AS Score_for_window,
    cs.ViewCount AS ViewCount_for_window,
    cs.PostTypeId AS PostTypeId_for_window,
    cs.PostId AS PostId_for_window,
    cs.OwnerUserId AS OwnerUserId_for_window,
    cs.CommentCount AS CommentCount_for_window,
    cs.UpVotes AS UpVotes_for_window,
    cs.DownVotes AS DownVotes_for_window,
    rap.Tags AS Tags
  FROM CorrelatedStats cs
  LEFT JOIN Users u ON cs.OwnerUserId = u.Id
  LEFT JOIN RecentActivePosts rap ON cs.PostId = rap.PostId
),
Windowed AS (
  SELECT
    pc.PostId,
    pc.PostTypeId,
    pc.OwnerUserId,
    pc.Score,
    pc.ViewCount,
    pc.CommentCount,
    pc.UpVotes,
    pc.DownVotes,
    pc.ScorePerView,
    pc.NetVotes,
    pc.OwnerLocation,
    pc.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY pc.PostTypeId
      ORDER BY pc.Score DESC, pc.ViewCount DESC, pc.PostId DESC
    ) AS rn
  FROM ComplexComputed pc
)
SELECT
  w.PostId,
  w.PostTypeId,
  w.OwnerUserId,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.UpVotes,
  w.DownVotes,
  w.ScorePerView,
  w.NetVotes,
  w.OwnerLocation,
  rt.TagName,
  rt.TagPostCount
FROM Windowed w
LEFT JOIN TopTags rt ON POSITION(rt.TagName IN COALESCE(w.Tags, '')) > 0
WHERE w.rn <= 5
  OR rt.TagPostCount IS NOT NULL
ORDER BY w.PostTypeId, w.Score DESC, w.ViewCount DESC
LIMIT 100;