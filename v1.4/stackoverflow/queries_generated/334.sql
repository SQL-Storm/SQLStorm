-- {"query": "334.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 12443} 
WITH
  AllPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.Views,
      p.CommentCount,
      p.FavoriteCount,
      p.AcceptedAnswerId,
      p.ParentId,
      p.Body,
      p.ContentLicense,
      CASE WHEN p.Tags IS NULL THEN 0
           ELSE array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
      END AS TagCount,
      CASE WHEN p.Tags IS NULL THEN NULL
           ELSE split_part(substring(p.Tags, 2, length(p.Tags)-2), '><', 1)
      END AS TopTag,
      COALESCE((SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10), 0) AS TotalCloseVotes
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
  ),
  WithRank AS (
    SELECT
      PostId,
      Title,
      OwnerUserId,
      OwnerDisplayName,
      LastActivityDate,
      Score,
      Views,
      CommentCount,
      FavoriteCount,
      PostTypeId,
      TagCount,
      TopTag,
      TotalCloseVotes,
      ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY LastActivityDate DESC) AS RecentRank,
      ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC) AS ScoreRank
    FROM AllPosts
  ),
  TopRecent AS (
    SELECT
      PostId,
      Title,
      OwnerUserId,
      OwnerDisplayName,
      LastActivityDate,
      Score,
      Views,
      CommentCount,
      FavoriteCount,
      PostTypeId,
      TagCount,
      TopTag,
      TotalCloseVotes,
      1 AS SourceGroup,
      RecentRank AS UserRank
    FROM WithRank
    WHERE RecentRank = 1
  ),
  TopScore AS (
    SELECT
      PostId,
      Title,
      OwnerUserId,
      OwnerDisplayName,
      LastActivityDate,
      Score,
      Views,
      CommentCount,
      FavoriteCount,
      PostTypeId,
      TagCount,
      TopTag,
      TotalCloseVotes,
      2 AS SourceGroup,
      ScoreRank AS UserRank
    FROM WithRank
    WHERE ScoreRank = 1
  ),
  Combined AS (
    SELECT * FROM TopRecent
    UNION ALL
    SELECT * FROM TopScore
  )
SELECT
  PostId,
  Title,
  OwnerUserId,
  OwnerDisplayName,
  LastActivityDate,
  Score,
  Views,
  CommentCount,
  FavoriteCount,
  PostTypeId,
  TagCount,
  TopTag,
  TotalCloseVotes,
  SourceGroup,
  UserRank
FROM Combined
ORDER BY SourceGroup, LastActivityDate DESC
LIMIT 300;