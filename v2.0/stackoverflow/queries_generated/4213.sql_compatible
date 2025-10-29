WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Users u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 7, 8)
  ),
  MostRecentEdit AS (
    SELECT
      PostId,
      EditorDisplayName,
      EditDate
    FROM RankedPostEdits
    WHERE
      rn = 1
  ),
  UserQuestionCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS QuestionCount,
      SUM(p.ViewCount) AS TotalViewCount,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AverageScore
    FROM Posts p
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.OwnerUserId
  ),
  AnswerStats AS (
    SELECT
      p.ParentId,
      COUNT(p.Id) AS AnswerCount,
      SUM(p.Score) AS TotalAnswerScore,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AverageAnswerScore,
      SUM(CASE WHEN p.Id = ps.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts p
    LEFT JOIN Posts ps
      ON p.Id = ps.AcceptedAnswerId
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  PostWithDetails AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Tags,
      p.CreationDate AS PostCreationDate,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE
        WHEN mre.EditorDisplayName IS NOT NULL THEN mre.EditorDisplayName
        ELSE 'Community'
      END AS LastEditor,
      mre.EditDate AS LastEditDate,
      COALESCE(uq.QuestionCount, 0) AS UserTotalQuestions,
      COALESCE(uq.TotalViewCount, 0) AS UserTotalQuestionViews,
      COALESCE(uq.AverageScore, 0.0) AS UserAverageQuestionScore,
      COALESCE(ans.AnswerCount, 0) AS NumberOfAnswers,
      COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
      COALESCE(ans.AverageAnswerScore, 0.0) AS AverageAnswerScore,
      COALESCE(ans.AcceptedAnswerCount, 0) AS AcceptedAnswers
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN MostRecentEdit mre
      ON p.Id = mre.PostId
    LEFT JOIN UserQuestionCounts uq
      ON p.OwnerUserId = uq.OwnerUserId
    LEFT JOIN AnswerStats ans
      ON p.Id = ans.ParentId
    WHERE
      p.PostTypeId = 1
      AND p.ClosedDate IS NULL
  )
SELECT
  pwd.PostId,
  pwd.Title,
  pwd.Tags,
  pwd.PostCreationDate,
  pwd.OwnerDisplayName,
  pwd.PostScore,
  pwd.PostViewCount,
  pwd.PostCommentCount,
  pwd.PostFavoriteCount,
  pwd.LastEditor,
  pwd.LastEditDate,
  pwd.UserTotalQuestions,
  pwd.UserTotalQuestionViews,
  pwd.UserAverageQuestionScore,
  pwd.NumberOfAnswers,
  pwd.TotalAnswerScore,
  pwd.AverageAnswerScore,
  pwd.AcceptedAnswers,
  CASE
    WHEN pwd.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipStatus,
  (
    SELECT
      COUNT(*)
    FROM Votes v
    WHERE
      v.PostId = pwd.PostId AND v.VoteTypeId = 2
  ) AS UpVoteCount,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = pwd.PostId
      AND c.CreationDate >= pwd.PostCreationDate
      AND c.CreationDate <= pwd.LastEditDate
  ) AS CommentsSinceLastEdit,
  (
    SELECT
      STRING_AGG(lt.Name || ': ' || CAST(rl.RelatedPostId AS TEXT), ', ' ORDER BY lt.Name)
    FROM PostLinks rl
    JOIN LinkTypes lt
      ON rl.LinkTypeId = lt.Id
    WHERE
      rl.PostId = pwd.PostId
  ) AS RelatedPosts,
  CASE
    WHEN pwd.PostScore > 100 THEN 'High Score'
    WHEN pwd.PostScore > 20 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  UPPER(SUBSTRING(pwd.OwnerDisplayName FROM 1 FOR 3)) AS OwnerDisplayNameInitials,
  CASE
    WHEN pwd.UserTotalQuestions > 1000 THEN 'Prolific'
    WHEN pwd.UserTotalQuestions > 100 THEN 'Experienced'
    ELSE 'Novice'
  END AS UserExperienceLevel,
  EXTRACT(YEAR FROM pwd.PostCreationDate) AS PostCreationYear,
  CASE
    WHEN pwd.PostViewCount > (
      SELECT
        AVG(ViewCount)
      FROM Posts
      WHERE
        PostTypeId = 1
    ) THEN 'Above Average Views'
    ELSE 'Below Average Views'
  END AS ViewCountBenchmark
FROM PostWithDetails pwd
WHERE
  pwd.PostViewCount > 0
  AND pwd.NumberOfAnswers > 0
  AND pwd.PostCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
ORDER BY
  pwd.PostScore DESC,
  pwd.PostCreationDate ASC
LIMIT 100;