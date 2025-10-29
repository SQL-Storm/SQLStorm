WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_owner,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.Tags, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, u.DisplayName
),
TaggedActivity AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    STRING_AGG(DISTINCT CAST(p.Id AS varchar), ',') AS SampleQuestionIds
  FROM Tags t
  JOIN Posts p ON t.Id = CAST(p.Tags AS int)
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
CrossJoinStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.OwnerName,
    r.CommentCount,
    r.UpVotes,
    r.DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId) AS LinkCount,
    (SELECT COUNT(*) FROM Votes vo WHERE vo.PostId = r.PostId AND vo.VoteTypeId = 14) AS ModeratorVotes,
    r.rn_owner
  FROM RecentTopQuestions r
  WHERE r.rn_owner = 1
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  c.OwnerName,
  c.CommentCount,
  c.UpVotes,
  c.DownVotes,
  c.LinkCount,
  c.ModeratorVotes,
  COALESCE(t.sample_quality, 'Unknown') AS SampleQuality
FROM CrossJoinStats c
LEFT JOIN (
  SELECT
    'High' AS sample_quality
) t ON 1=1
ORDER BY c.Score DESC, c.CreationDate DESC
FETCH FIRST 100 ROWS ONLY;