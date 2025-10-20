-- {"query": "62.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1199} 
WITH
  -- 1) Recent activity per post with wildcard window function
  PostActivity AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ContentLicense,
      -- compute a dynamic rank of activity within 30 days window per post type
      ROW_NUMBER() OVER (
        PARTITION BY p.PostTypeId
        ORDER BY GREATEST(p.LastActivityDate, p.CreationDate) DESC
      ) AS TypeRank,
      -- Define a compact activity score combining views and score
      (p.ViewCount * 2 + p.Score * 5 + COALESCE(pc.TotalCommentScore,0)) AS ActivityScore
    FROM Posts p
    LEFT JOIN (
      SELECT PostId, SUM(Score) AS TotalCommentScore
      FROM Comments
      GROUP BY PostId
    ) pc ON pc.PostId = p.Id
  ),

  -- 2) Tag-based influence: join with Tags to get tag popularity and excerpts
  TagInfo AS (
    SELECT
      t.Id AS TagId,
      t.TagName,
      t.Count AS TagCount,
      t.IsModeratorOnly,
      t.IsRequired,
      p.Id AS PostIdForTag,
      EXTRACT(EPOCH FROM (CURRENT_DATE - p.CreationDate))/86400 AS AgeDays
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.TagName IS NOT NULL
  ),

  -- 3) Complex correlated subquery: posts with recent close history from PostHistory
  CloseVotes AS (
    SELECT
      ph.PostId,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseDate,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS LastCloseReasonComment,
      COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteCount
    FROM PostHistory ph
    GROUP BY ph.PostId
  ),

  -- 4) Windowed aggregation: per user, top posts by activity score in last 365 days
  UserTopPosts AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      p.Id AS PostId,
      p.Title,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      p.Tags,
      ROW_NUMBER() OVER (
        PARTITION BY u.Id
        ORDER BY p.LastActivityDate DESC, p.Score DESC
      ) AS UserPostRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.LastActivityDate >= CURRENT_DATE - INTERVAL '365 days'
  ),

  -- 5) Set-operation style: unioned representation of questions and answers with nuanced predicates
  UnifiedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ContentLicense,
      NULL AS ExtraInfo
    FROM Posts p
    WHERE
      p.PostTypeId IN (1,2) -- only Questions and Answers
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    UNION ALL
    SELECT
      p.Id,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ContentLicense,
      'Archived' AS ExtraInfo
    FROM Posts p
    WHERE p.PostTypeId = 5 -- TagWiki
  )

SELECT
  -- Post identifiers
  UP.PostId,
  UP.Title,
  UP.PostTypeId,
  UP.OwnerUserId,
  U.DisplayName AS OwnerDisplayName,
  UP.CreationDate,
  UP.LastActivityDate,
  UP.Score,
  UP.ViewCount,
  UP.Tags,
  UP.AnswerCount,
  UP.CommentCount,
  UP.FavoriteCount,
  UP.ContentLicense,
  -- Rich metrics
  COALESCE(A.ActivityScore, 0) AS ActivityScore,
  A.TypeRank,
  TI.TagName,
  TI.TagCount,
  COALESCE(CV.LastCloseDate, NULL) AS LastCloseDate,
  COALESCE(CV.CloseVoteCount, 0) AS CloseVoteCount,
  ROW_NUMBER() OVER (
    PARTITION BY UP.PostTypeId
    ORDER BY COALESCE(A.ActivityScore,0) DESC, UP.LastActivityDate DESC
  ) AS GlobalRank,
  UP.ExtraInfo

FROM UnifiedPosts UP
LEFT JOIN Users U ON UP.OwnerUserId = U.Id
LEFT JOIN PostActivity A ON UP.PostId = A.PostId
LEFT JOIN TagInfo TI ON UP.PostId = TI.PostIdForTag
LEFT JOIN CloseVotes CV ON UP.PostId = CV.PostId
WHERE
  UP.PostTypeId IN (1,2,5)
  AND UP.LastActivityDate IS NOT NULL
  AND (UP.ViewCount > 0 OR UP.Score > 0)
ORDER BY GlobalRank, UP.LastActivityDate DESC
LIMIT 100;