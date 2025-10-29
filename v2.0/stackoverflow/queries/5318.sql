WITH RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY
),
TopTagVoters AS (
  SELECT
    tt.TagName,
    v.UserId,
    v.CreationDate,
    COUNT(*) OVER (PARTITION BY tt.TagName) AS tagVotes
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  -- split tags using standard SQL: remove angle brackets, replace with commas, then split by comma using a recursive CTE
  JOIN LATERAL (
    WITH RECURSIVE parts(idx, rest, part) AS (
      SELECT
        1,
        TRIM(BOTH ' ' FROM REPLACE(REPLACE(COALESCE(p.Tags, ''), '<', ''), '>', ',')),
        NULL
      UNION ALL
      SELECT
        idx + 1,
        CASE
          WHEN POSITION(',' IN rest) > 0 THEN SUBSTR(rest, POSITION(',' IN rest) + 1)
          ELSE ''
        END,
        CASE
          WHEN POSITION(',' IN rest) > 0 THEN TRIM(BOTH ' ' FROM SUBSTR(rest, 1, POSITION(',' IN rest) - 1))
          ELSE TRIM(BOTH ' ' FROM rest)
        END
      FROM parts
      WHERE rest <> ''
    )
    SELECT part AS tag
    FROM parts
    WHERE part IS NOT NULL AND part <> ''
  ) AS t ON TRUE
  JOIN Tags tt ON tt.TagName = t.tag
  WHERE v.VoteTypeId = 2
    AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365' DAY
),
Competition AS (
  SELECT
    rtp.PostId,
    rtp.Title,
    rtp.CreationDate,
    rtp.Score,
    rtp.ViewCount,
    rtp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT vl.UserId) AS UniqueVoters,
    AVG(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount END) AS AvgBounty,
    MAX(v.CreationDate) AS LastVoteDate
  FROM RecentTopPosts rtp
  LEFT JOIN Votes v ON v.PostId = rtp.PostId
  LEFT JOIN Users u ON u.Id = rtp.OwnerUserId
  LEFT JOIN Votes vl ON vl.PostId = rtp.PostId AND vl.VoteTypeId = 2
  WHERE rtp.rn <= 5
  GROUP BY
    rtp.PostId, rtp.Title, rtp.CreationDate, rtp.Score, rtp.ViewCount,
    rtp.OwnerUserId, u.DisplayName, u.Reputation
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Reputation,
  c.UniqueVoters,
  c.AvgBounty,
  c.LastVoteDate,
  ht.Name AS HistoryTypeName,
  cl.Name AS CloseReason
FROM Competition c
LEFT JOIN PostHistory ph ON ph.PostId = c.PostId
LEFT JOIN PostHistoryTypes ht ON ht.Id = ph.PostHistoryTypeId
LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
LEFT JOIN CloseReasonTypes cl ON cl.Id = CAST(
  NULLIF(
    TRIM(BOTH '"' FROM
      COALESCE(
        regexp_replace(COALESCE(ph.Text, ''), '.*"CloseReasonId"\s*:\s*"*([^",}]+)".*', '\1'),
        ''
      )
    ),
    ''
  ) AS SMALLINT
)
WHERE
  ph.Id IS NULL OR ph.CreationDate = (
    SELECT MAX(ph2.CreationDate)
    FROM PostHistory ph2
    WHERE ph2.PostId = c.PostId
  )
ORDER BY c.LastVoteDate DESC
LIMIT 100;