-- {"query": "4600.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1820} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ph.Text AS HistoryText,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestEdits AS (
    SELECT
      rph.PostId,
      rph.UserId AS LastEditorUserId,
      rph.CreationDate AS LastEditDate,
      rph.HistoryText AS LatestEditBody,
      (
        SELECT
          p.Title
        FROM Posts AS p
        WHERE
          p.Id = rph.PostId
      ) AS OriginalTitle
    FROM RankedPostHistory AS rph
    WHERE
      rph.rn = 1
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.ViewCount) AS MaxViewCount,
      SUM(p.FavoriteCount) AS TotalFavorites
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      (
        SELECT
          COUNT(*)
        FROM Posts AS p
        WHERE
          p.Tags LIKE '%' || t.TagName || '%'
      ) AS PostsWithTagCount
    FROM Tags AS t
    ORDER BY
      t.Count DESC
    LIMIT 100
  ),
  ComplexPost AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      COALESCE(u.DisplayName, p.OwnerDisplayName) AS DisplayName,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.Tags,
      le.LastEditDate,
      le.LatestEditBody,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.PostId = p.Id
      ) AS CommentCountSubquery,
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM PostLinks AS pl
          WHERE
            pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) THEN 'Is Duplicate'
        ELSE 'Not Duplicate'
      END AS DuplicateStatus,
      CASE
        WHEN p.Title IS NOT NULL THEN SUBSTRING(p.Title FROM 1 FOR 50) || '...'
        ELSE 'No Title'
      END AS TruncatedTitle,
      (
        SELECT
          STRING_AGG(lt.Name, ', ')
        FROM PostLinks AS pl
        JOIN LinkTypes AS lt
          ON pl.LinkTypeId = lt.Id
        WHERE
          pl.PostId = p.Id
      ) AS LinkedPostTypes,
      LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
      (
        SELECT
          SUM(v.BountyAmount)
        FROM Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 8
      ) AS TotalBountyAmount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostTypeRankByScore
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN LatestEdits AS le
      ON p.Id = le.PostId
    WHERE
      p.Score > 10 AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  )
SELECT
  cp.PostId,
  cp.PostTypeName,
  cp.DisplayName,
  cp.CreationDate,
  cp.Score,
  cp.ViewCount,
  cp.TruncatedTitle,
  cp.PostStatus,
  cp.DuplicateStatus,
  cp.LinkedPostTypes,
  cp.NextPostScore,
  cp.PreviousPostScore,
  cp.TotalBountyAmount,
  cp.PostTypeRankByScore,
  tp.TagName AS TopTag,
  tp.TagCount AS TopTagCount,
  uc.Reputation AS OwnerReputation,
  uc.PostCount AS OwnerTotalPosts,
  uc.AnswerCount AS OwnerAnswerCount,
  CASE
    WHEN cp.LatestEditBody IS NULL THEN 'No Recent Edit'
    WHEN LENGTH(cp.LatestEditBody) > 100 THEN SUBSTRING(cp.LatestEditBody FROM 1 FOR 100) || '...'
    ELSE cp.LatestEditBody
  END AS SnippetOfLatestEdit,
  CASE
    WHEN cp.OwnerUserId IS NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipType,
  CONCAT(cp.Score, '-', cp.ViewCount) AS ScoreViewCountConcat
FROM ComplexPost AS cp
LEFT JOIN TagPopularity AS tp
  ON cp.Tags LIKE '%' || tp.TagName || '%'
LEFT JOIN UserContribution AS uc
  ON cp.OwnerUserId = uc.UserId
WHERE
  cp.PostTypeRankByScore <= 50 AND cp.Score > 0
UNION
SELECT
  cp.PostId,
  cp.PostTypeName,
  cp.DisplayName,
  cp.CreationDate,
  cp.Score,
  cp.ViewCount,
  cp.TruncatedTitle,
  cp.PostStatus,
  cp.DuplicateStatus,
  cp.LinkedPostTypes,
  cp.NextPostScore,
  cp.PreviousPostScore,
  cp.TotalBountyAmount,
  cp.PostTypeRankByScore,
  tp.TagName AS TopTag,
  tp.TagCount AS TopTagCount,
  uc.Reputation AS OwnerReputation,
  uc.PostCount AS OwnerTotalPosts,
  uc.AnswerCount AS OwnerAnswerCount,
  CASE
    WHEN cp.LatestEditBody IS NULL THEN 'No Recent Edit'
    WHEN LENGTH(cp.LatestEditBody) > 100 THEN SUBSTRING(cp.LatestEditBody FROM 1 FOR 100) || '...'
    ELSE cp.LatestEditBody
  END AS SnippetOfLatestEdit,
  CASE
    WHEN cp.OwnerUserId IS NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipType,
  CONCAT(cp.Score, '-', cp.ViewCount) AS ScoreViewCountConcat
FROM ComplexPost AS cp
LEFT JOIN TagPopularity AS tp
  ON cp.Tags LIKE '%' || tp.TagName || '%'
LEFT JOIN UserContribution AS uc
  ON cp.OwnerUserId = uc.UserId
WHERE
  cp.PostTypeName = 'Question' AND cp.Score <= 0 AND cp.CreationDate > '2023-06-01';
