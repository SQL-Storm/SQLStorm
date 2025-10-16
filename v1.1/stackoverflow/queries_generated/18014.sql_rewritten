-- {"query": "18014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2044} 
WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      COUNT(DISTINCT c.Id) AS CommentCountPerPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      (
        SELECT
          COUNT(*)
        FROM
          PostHistory ph
        WHERE
          ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS EditHistoryCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RowNumByType
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Comments c
        ON p.Id = c.PostId
      LEFT JOIN Votes v
        ON p.Id = v.PostId
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
      AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      u.Reputation AS UserReputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT pe.PostId) AS TotalPosts,
      SUM(pe.PostScore) AS TotalPostScore,
      AVG(pe.PostViewCount) AS AvgPostViewCount,
      SUM(CASE WHEN pe.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pe.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(pe.PostCreationDate) AS LatestPostDate,
      STRING_AGG(DISTINCT pe.PostTypeName, ', ') AS PostTypesEngagedWith
    FROM
      Users u
      LEFT JOIN PostEngagement pe
        ON u.Id = pe.OwnerUserId
      LEFT JOIN Badges b
        ON u.Id = b.UserId
    WHERE
      u.Id > 0
      AND u.Id NOT IN (
        SELECT
          UserId
        FROM
          PostHistory
        WHERE
          PostHistoryTypeId = 16
      ) -- Exclude community-owned users
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  ue.UserId,
  ue.UserDisplayName,
  ue.UserReputation,
  ue.UserCreationDate,
  ue.UserViews,
  ue.UserUpVotes,
  ue.UserDownVotes,
  ue.TotalPosts,
  ue.TotalPostScore,
  ue.AvgPostViewCount,
  ue.QuestionCount,
  ue.AnswerCount,
  ue.BadgeCount,
  ue.LatestPostDate,
  ue.PostTypesEngagedWith,
  CASE
    WHEN ue.TotalPosts > 1000 THEN 'Prolific'
    WHEN ue.TotalPosts > 100 THEN 'Experienced'
    WHEN ue.TotalPosts > 10 THEN 'Active'
    ELSE 'Newbie'
  END AS UserActivityLevel,
  CASE
    WHEN ue.UserReputation > 50000 THEN 'Expert'
    WHEN ue.UserReputation > 10000 THEN 'Advanced'
    WHEN ue.UserReputation > 1000 THEN 'Intermediate'
    ELSE 'Novice'
  END AS UserReputationLevel,
  pe.PostId,
  pe.PostTypeId,
  pe.PostTypeName,
  pe.PostCreationDate,
  pe.PostScore,
  pe.PostViewCount,
  pe.PostAnswerCount,
  pe.PostCommentCount,
  pe.PostFavoriteCount,
  pe.ClosedDate,
  pe.CommentCountPerPost,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.EditHistoryCount,
  pe.RowNumByType,
  CONCAT(
    pe.PostTypeName,
    ' - Score: ',
    pe.PostScore,
    ' - Answers: ',
    pe.PostAnswerCount
  ) AS PostSummary,
  CASE
    WHEN pe.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  DENSE_RANK() OVER (
    ORDER BY
      ue.UserReputation DESC,
      ue.TotalPosts DESC
  ) AS UserGlobalRank,
  RANK() OVER (PARTITION BY pe.PostTypeId ORDER BY pe.PostScore DESC) AS PostRankByType,
  LEAD(pe.PostCreationDate, 1, '1970-01-01') OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate) AS NextPostDateByOwner,
  LAG(pe.PostScore, 1, 0) OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate) AS PreviousPostScoreByOwner,
  SUM(pe.PostScore) OVER (PARTITION BY pe.OwnerUserId) AS TotalScoreByUser,
  AVG(pe.PostScore) OVER (PARTITION BY pe.OwnerUserId) AS AvgScoreByUser,
  CASE
    WHEN pe.PostTypeId = 1 THEN (
      SELECT
        COUNT(*)
      FROM
        PostLinks pl
      WHERE
        pl.PostId = pe.PostId AND pl.LinkTypeId = 3
    )
    ELSE 0
  END AS DuplicateLinkCount,
  CASE
    WHEN pe.PostTypeId = 2 THEN (
      SELECT
        COUNT(*)
      FROM
        PostLinks pl
      WHERE
        pl.RelatedPostId = pe.PostId AND pl.LinkTypeId = 3
    )
    ELSE 0
  END AS DuplicateOfCount
FROM
  UserEngagement ue
LEFT OUTER JOIN
  PostEngagement pe
  ON ue.UserId = pe.OwnerUserId
WHERE
  pe.PostId IS NOT NULL
  OR ue.TotalPosts > 0
UNION
SELECT
  NULL AS UserId,
  NULL AS UserDisplayName,
  NULL AS UserReputation,
  NULL AS UserCreationDate,
  NULL AS UserViews,
  NULL AS UserUpVotes,
  NULL AS UserDownVotes,
  NULL AS TotalPosts,
  NULL AS TotalPostScore,
  NULL AS AvgPostViewCount,
  NULL AS QuestionCount,
  NULL AS AnswerCount,
  NULL AS BadgeCount,
  NULL AS LatestPostDate,
  NULL AS PostTypesEngagedWith,
  NULL AS UserActivityLevel,
  NULL AS UserReputationLevel,
  NULL AS PostId,
  NULL AS PostTypeId,
  NULL AS PostTypeName,
  NULL AS PostCreationDate,
  NULL AS PostScore,
  NULL AS PostViewCount,
  NULL AS PostAnswerCount,
  NULL AS PostCommentCount,
  NULL AS PostFavoriteCount,
  NULL AS ClosedDate,
  NULL AS CommentCountPerPost,
  NULL AS UpVoteCount,
  NULL AS DownVoteCount,
  NULL AS EditHistoryCount,
  NULL AS RowNumByType,
  'Summary Statistics' AS PostSummary,
  NULL AS PostStatus,
  NULL AS UserGlobalRank,
  NULL AS PostRankByType,
  NULL AS NextPostDateByOwner,
  NULL AS PreviousPostScoreByOwner,
  SUM(pe.PostScore) AS TotalScoreByUser,
  AVG(pe.PostScore) AS AvgScoreByUser,
  NULL AS DuplicateLinkCount,
  NULL AS DuplicateOfCount
FROM
  PostEngagement pe;