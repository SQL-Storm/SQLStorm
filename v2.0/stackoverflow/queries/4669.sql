WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.OwnerUserId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      SUM(p.ViewCount) AS TotalViews
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AverageCommentScore,
      SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    GROUP BY
      c.PostId
  ),
  PostInteraction AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT v.UserId) AS DistinctVoterCount,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS DuplicateOfPostId
    FROM Posts AS p
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    LEFT JOIN PostLinks AS pl
      ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    GROUP BY
      p.Id
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.PostTypeName,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  upa.DisplayName AS OwnerDisplayName,
  upa.TotalPosts AS OwnerTotalPosts,
  upa.QuestionCount AS OwnerQuestionCount,
  upa.AnswerCount AS OwnerAnswerCount,
  upa.AverageScore AS OwnerAverageScore,
  ca.CommentCount,
  ca.AverageCommentScore,
  ca.AnonymousCommentCount,
  pi.DistinctVoterCount,
  pi.UpVoteCount,
  pi.DownVoteCount,
  CASE
    WHEN ca.LastCommentDate > rp.CreationDate THEN 'Comments Newer Than Last Activity'
    WHEN ca.LastCommentDate IS NULL THEN 'No Comments'
    ELSE 'Last Comment Older Than Last Activity'
  END AS CommentActivityStatus,
  CASE
    WHEN pi.DuplicateOfPostId IS NOT NULL THEN 'Is Duplicate'
    ELSE 'Not Duplicate'
  END AS DuplicateStatus,
  REPLACE(SUBSTRING(rp.Title FROM 1 FOR 10), 'a', 'X') AS ModifiedTitleSnippet,
  COALESCE(upa.TotalViews, 0) AS SafeTotalViews
FROM RankedPosts AS rp
LEFT JOIN UserPostActivity AS upa
  ON rp.OwnerUserId = upa.UserId
LEFT JOIN CommentAnalysis AS ca
  ON rp.PostId = ca.PostId
LEFT JOIN PostInteraction AS pi
  ON rp.PostId = pi.PostId
WHERE
  rp.rn <= 100
  AND rp.Score > 0
  AND upa.TotalPosts > 50
  AND (
    upa.AverageScore > 10 OR upa.AnswerCount > 20
  )
  AND ca.CommentCount > 5
ORDER BY
  rp.Score DESC,
  rp.ViewCount DESC;