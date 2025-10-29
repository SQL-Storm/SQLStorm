-- {"query": "5459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 923}
WITH
RecentPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditDate,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_type
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
AuthorStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(b.TotalBadges,0) AS BadgeCount,
    COALESCE(v.TotalVotes,0) AS VoteCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalVotes
    FROM Votes
    GROUP BY UserId
  ) v ON v.UserId = u.Id
),
TagAnalytics AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    AVG(p.Score) AS AvgScorePerQuestion,
    SUM(p.ViewCount) AS TotalViews
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
  GROUP BY t.TagName
),
JoinedData AS (
  SELECT
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.LastActivityDate,
    a.DisplayName AS AuthorName,
    a.Reputation AS AuthorRep,
    a.BadgeCount,
    a.VoteCount,
    rg.DisplayName AS LastEditorName,
    cl.Name AS CloseReason,
    ph.Comment AS PhComment,
    rp.OwnerUserId,
    ph.PostId AS PhPostId,
    ph.PostHistoryTypeId AS PhTypeId,
    ph2.PostId AS Ph2PostId,
    ph2.PostHistoryTypeId AS Ph2TypeId
  FROM RecentPosts rp
  LEFT JOIN AuthorStats a ON rp.OwnerUserId = a.UserId
  LEFT JOIN PostHistory ph ON ph.PostId = rp.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN Users rg ON rg.Id = ph.UserId
  LEFT JOIN PostHistory ph2 ON ph2.PostId = rp.Id AND ph2.PostHistoryTypeId = 11
  LEFT JOIN CloseReasonTypes cl ON CAST(ph.Comment AS varchar) = CAST(cl.Id AS varchar)
  WHERE rp.rn_type = 1
),
ComplexFilters AS (
  SELECT
    jd.PostId,
    jd.PostTypeId,
    jd.Title,
    jd.Tags,
    jd.CreationDate,
    jd.Score,
    jd.ViewCount,
    jd.LastActivityDate,
    jd.AuthorName,
    jd.AuthorRep,
    jd.BadgeCount,
    jd.VoteCount,
    jd.LastEditorName,
    jd.CloseReason,
    CASE
      WHEN jd.PostTypeId = 1 THEN 'Question'
      WHEN jd.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    (jd.Score * 1.0) / NULLIF(jd.ViewCount,0) AS ScorePerView,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) AS AvgQuestionScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = jd.PostId AND v.VoteTypeId = 2) AS UpvotesOnPost
  FROM JoinedData jd
  GROUP BY
    jd.PostId,
    jd.PostTypeId,
    jd.Title,
    jd.Tags,
    jd.CreationDate,
    jd.Score,
    jd.ViewCount,
    jd.LastActivityDate,
    jd.AuthorName,
    jd.AuthorRep,
    jd.BadgeCount,
    jd.VoteCount,
    jd.LastEditorName,
    jd.CloseReason
)
SELECT
  cf.PostId,
  cf.PostKind,
  cf.Title,
  cf.Tags,
  cf.CreationDate,
  cf.ViewCount,
  cf.Score,
  cf.LastActivityDate,
  cf.AuthorName,
  cf.AuthorRep,
  cf.BadgeCount,
  cf.VoteCount,
  cf.LastEditorName,
  cf.CloseReason,
  cf.ScorePerView,
  cf.AvgQuestionScore,
  cf.UpvotesOnPost
FROM ComplexFilters cf
LEFT JOIN PostLinks pl ON pl.PostId = cf.PostId AND pl.LinkTypeId = 1
LEFT JOIN Posts related ON related.Id = pl.RelatedPostId
ORDER BY cf.LastActivityDate DESC
LIMIT 200;