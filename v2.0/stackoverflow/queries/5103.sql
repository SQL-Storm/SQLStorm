-- {"query": "5103.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 843}
WITH MostActiveUsers AS (
  SELECT
    u.id AS UserId,
    u.displayname,
    u.reputation,
    COUNT(p.id) AS PostCount,
    SUM(p.score) AS TotalPostScore,
    MAX(p.creationdate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.owneruserid = u.id
  GROUP BY u.id, u.displayname, u.reputation
),
TopTags AS (
  SELECT
    t.tagname,
    t.count,
    t.excerptpostid,
    t.wikipostid,
    ROW_NUMBER() OVER (ORDER BY t.count DESC, t.tagname ASC) AS rn
  FROM Tags t
  WHERE t.ismoderatoronly = FALSE
),
RecentClosed AS (
  SELECT
    ph.postid,
    ph.posthistorytypeid,
    ph.creationdate,
    ph.comment,
    rc.name AS closereasonname
  FROM PostHistory ph
  LEFT JOIN CloseReasonTypes rc ON CAST(ph.comment AS varchar) LIKE '%' || CAST(rc.id AS varchar) || '%'
  WHERE ph.posthistorytypeid = 10
    AND ph.creationdate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
),
MixedSample AS (
  SELECT
    u.UserId AS UserId,
    u.DisplayName AS UserName,
    p.id AS PostId,
    p.title,
    p.tags,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    v.VoteCount
  FROM MostActiveUsers u
  CROSS JOIN LATERAL (
    SELECT *
    FROM Posts p
    WHERE p.owneruserid = u.UserId
    ORDER BY p.creationdate DESC
    LIMIT 1
  ) p
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS VoteCount
    FROM Votes vs
    WHERE vs.postid = p.id
      AND vs.votetypeid IN (2, 6, 7, 8, 9, 10, 11, 12)
  ) v ON TRUE
  WHERE p.posttypeid IN (1, 2)
),
WindowedStats AS (
  SELECT
    p.id AS PostId,
    p.title,
    p.tags,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    ROW_NUMBER() OVER (
      ORDER BY p.score DESC NULLS LAST,
               p.viewcount DESC NULLS LAST,
               p.creationdate ASC
    ) AS rn_desc,
    SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) OVER (
      PARTITION BY p.id
    ) AS UpvotesOnPost
  FROM Posts p
  LEFT JOIN Votes v ON v.postid = p.id
  GROUP BY p.id, p.title, p.tags, p.score, p.viewcount, p.creationdate, p.lastactivitydate, v.votetypeid
),
Filtered AS (
  SELECT
    ws.PostId,
    ws.title,
    ws.tags,
    ws.score,
    ws.viewcount,
    ws.creationdate,
    ws.lastactivitydate,
    ws.rn_desc,
    ws.UpvotesOnPost
  FROM WindowedStats ws
  WHERE ws.rn_desc <= 5
),
Annotated AS (
  SELECT
    f.PostId,
    f.title,
    f.tags,
    f.score,
    f.viewcount,
    f.creationdate,
    f.lastactivitydate,
    f.UpvotesOnPost,
    tt.rn,
    tt.tagname
  FROM Filtered f
  LEFT JOIN TopTags tt ON LOWER(f.title) LIKE '%' || LOWER(tt.tagname) || '%'
)
SELECT
  a.PostId,
  a.title,
  a.tags,
  a.score,
  a.viewcount,
  a.creationdate,
  a.lastactivitydate,
  a.UpvotesOnPost,
  a.tagname AS RelatedTag,
  a.rn
FROM Annotated a
LEFT JOIN RecentClosed rc ON rc.postid = a.PostId
WHERE a.UpvotesOnPost IS NOT NULL
ORDER BY a.score DESC NULLS LAST, a.viewcount DESC NULLS LAST
LIMIT 200;