WITH prioritized_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
    AND (p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 months')
),
recent_hot AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS HistoryDate,
    ph.Text AS HistoryText,
    ph.PostHistoryTypeId,
    ph.UserId AS HistoryUserId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (16, 50, 52, 53) -- community owned, hot network, etc.
),
complex_metrics AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.Tags,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 8) AS AvgOpenBounty,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = q.Id) AS LastVoteDate,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagList
  FROM Posts q
  -- Extract first tag in a SQL-dialect-neutral way assuming Tags is a JSON array text like '["tag1","tag2"]'.
  -- Replace JSON_VALUE(...) with a safe substring/extraction: find second double-quote and third double-quote positions.
  LEFT JOIN Tags t ON t.Id = NULL -- placeholder; see join below in correlated form
  WHERE q.PostTypeId = 1
    AND q.ClosedDate IS NULL
  GROUP BY q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.Tags
),
-- Because standard SQL has no portable JSON_VALUE, use a lateral/correlated approach to extract first tag text and join to Tags.
first_tag_extracted AS (
  SELECT
    q.Id AS QuestionId,
    q.Tags,
    -- Extract first tag string between the first pair of double quotes after the opening bracket.
    CASE
      WHEN POSITION('"' IN q.Tags) = 0 THEN NULL
      ELSE
        SUBSTRING(
          q.Tags FROM
          (POSITION('"' IN q.Tags) + 1) FOR
          (POSITION('"' IN SUBSTRING(q.Tags FROM POSITION('"' IN q.Tags) + 1)) - 1)
        )
    END AS FirstTagText
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.ClosedDate IS NULL
),
tag_joined AS (
  SELECT
    f.QuestionId,
    t.Id AS TagId,
    t.TagName
  FROM first_tag_extracted f
  LEFT JOIN Tags t ON t.TagName = f.FirstTagText
),
outer_join_example AS (
  SELECT
    pr.Id AS PostId,
    pr.Title,
    pr.CreationDate,
    pr.OwnerUserId,
    u.DisplayName AS OwnerName,
    pr.Score,
    pr.ViewCount,
    pr.Tags,
    recent_hot.HistoryDate AS RecentActivity,
    cl.Name AS CloseReason,
    pr.rn_owner,
    pr.LastActivityDate
  FROM prioritized_posts pr
  LEFT JOIN Users u ON pr.OwnerUserId = u.Id
  LEFT JOIN recent_hot ON recent_hot.PostId = pr.Id
  LEFT JOIN PostHistory ph ON ph.PostId = pr.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes cl ON CAST(ph.Comment AS VARCHAR(100)) LIKE '%' || cl.Id || '%'
  WHERE pr.rn_owner = 1
),
windowed AS (
  SELECT
    oje.PostId,
    oje.Title,
    oje.CreationDate,
    oje.OwnerUserId,
    oje.OwnerName,
    oje.Score,
    oje.ViewCount,
    oje.Tags,
    oje.RecentActivity,
    oje.CloseReason,
    ROW_NUMBER() OVER (ORDER BY oje.LastActivityDate DESC, oje.Score DESC) AS rn,
    oje.LastActivityDate
  FROM outer_join_example oje
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerName,
  w.Score,
  w.ViewCount,
  w.Tags AS TagList,
  w.RecentActivity,
  w.CloseReason
FROM windowed w
WHERE w.rn BETWEEN 1 AND 100
ORDER BY w.RecentActivity DESC, w.Score DESC;