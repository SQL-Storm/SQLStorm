WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.UserId IS NOT NULL
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostsOwned,
      SUM(p.ViewCount) AS TotalViews,
      AVG(p.Score) AS AvgScore,
      SUM(CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END) AS PostsWithAnswers
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
    GROUP BY
      p.OwnerUserId
  ),
  TopUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      upa.PostsOwned,
      upa.TotalViews,
      upa.AvgScore,
      upa.PostsWithAnswers
    FROM Users u
    JOIN UserPostActivity upa
      ON u.Id = upa.OwnerUserId
    WHERE
      u.Reputation > 10000
      AND u.Views > 50000
  ),
  RecentEditDetails AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS EditorUserId,
      rpe.CreationDate AS EditDate,
      rpe.PostHistoryTypeId AS EditTypeId,
      u.DisplayName AS EditorDisplayName,
      CASE
        WHEN rpe.PostHistoryTypeId = 4 THEN 'Title Edit'
        WHEN rpe.PostHistoryTypeId = 5 THEN 'Body Edit'
        WHEN rpe.PostHistoryTypeId = 6 THEN 'Tags Edit'
        ELSE 'Unknown Edit'
      END AS EditDescription,
      rpe.rn
    FROM RankedPostEdits rpe
    JOIN Users u
      ON rpe.UserId = u.Id
    WHERE
      rpe.rn <= 3
  )
SELECT
  tu.Id,
  tu.DisplayName AS TopUserDisplayName,
  tu.Reputation AS TopUserReputation,
  tu.CreationDate AS TopUserCreationDate,
  tu.PostsOwned AS TotalPostsOwnedByTopUser,
  tu.TotalViews AS TotalViewsOnTopUserPosts,
  tu.AvgScore AS AverageScoreOfTopUserPosts,
  tu.PostsWithAnswers AS TopUserPostsWithAnswers,
  COUNT(DISTINCT CASE WHEN red.EditTypeId = 4 THEN red.PostId END) AS PostsEditedTitleByTopUser,
  COUNT(DISTINCT CASE WHEN red.EditTypeId = 5 THEN red.PostId END) AS PostsEditedBodyByTopUser,
  COUNT(DISTINCT CASE WHEN red.EditTypeId = 6 THEN red.PostId END) AS PostsEditedTagsByTopUser,
  MAX(red.EditDate) AS LastEditDateByTopUserOrOthers,
  CASE
    WHEN tu.Reputation > 100000 THEN 'High Reputation'
    WHEN tu.Reputation BETWEEN 50000 AND 100000 THEN 'Medium-High Reputation'
    ELSE 'Medium Reputation'
  END AS ReputationTier
FROM TopUsers tu
LEFT JOIN RecentEditDetails red
  ON tu.Id = red.EditorUserId
GROUP BY
  tu.Id,
  tu.DisplayName,
  tu.Reputation,
  tu.CreationDate,
  tu.PostsOwned,
  tu.TotalViews,
  tu.AvgScore,
  tu.PostsWithAnswers
HAVING
  COUNT(red.PostId) > 0 OR tu.PostsOwned > 100
ORDER BY
  tu.Reputation DESC,
  tu.TotalViews DESC
FETCH FIRST 10 ROWS ONLY;