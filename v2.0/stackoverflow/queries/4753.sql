WITH
  PostActivity AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS RowNumDesc,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) AS RowNumAsc
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
  ),
  UserContributions AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COALESCE(u.Views, 0) AS UserViews,
      COALESCE(u.UpVotes, 0) AS UserUpVotes,
      COALESCE(u.DownVotes, 0) AS UserDownVotes,
      COUNT(DISTINCT pa_q.PostId) AS QuestionCount,
      COUNT(DISTINCT pa_a.PostId) AS AnswerCount,
      MAX(pa_q.PostCreationDate) AS LatestQuestionDate,
      MIN(pa_a.PostCreationDate) AS EarliestAnswerDate,
      AVG(EXTRACT(EPOCH FROM (pa_q.PostCreationDate - u.CreationDate)) / 86400.0) AS AvgDaysToFirstQuestion,
      AVG(EXTRACT(EPOCH FROM (pa_a.PostCreationDate - u.CreationDate)) / 86400.0) AS AvgDaysToFirstAnswer
    FROM Users u
    LEFT JOIN PostActivity pa_q
      ON u.Id = pa_q.OwnerUserId AND pa_q.PostTypeId = 1
    LEFT JOIN PostActivity pa_a
      ON u.Id = pa_a.OwnerUserId AND pa_a.PostTypeId = 2
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  ),
  TopContributors AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      UserCreationDate,
      UserViews,
      UserUpVotes,
      UserDownVotes,
      QuestionCount,
      AnswerCount,
      LatestQuestionDate,
      EarliestAnswerDate,
      AvgDaysToFirstQuestion,
      AvgDaysToFirstAnswer,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS RepRank
    FROM UserContributions
    WHERE QuestionCount > 50 OR AnswerCount > 100
  ),
  PostTags AS (
    SELECT
      p.Id AS PostId,
      TRIM(tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL (
      SELECT regexp_split_to_table(
               regexp_replace(COALESCE(p.Tags, ''), '[<>]', '', 'g'),
               '\s+'
             ) AS tag
    ) t
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
      AND TRIM(t.tag) <> ''
  ),
  PostAnalysis AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      CASE WHEN p.ClosedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400.0 ELSE NULL END AS DaysToClose,
      CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
      ptg.TagName,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost,
      SUM(v.VoteTypeId) OVER (PARTITION BY p.Id) AS TotalUpvotes,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS LatestRevisionNum
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN PostTags ptg
      ON p.Id = ptg.PostId AND p.PostTypeId = 1
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    LEFT JOIN Votes v
      ON p.Id = v.PostId AND v.VoteTypeId = 2
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0 AND p.CreationDate > TIMESTAMP '2023-01-01'
  )
SELECT
  tc.DisplayName AS TopContributorName,
  tc.Reputation AS ContributorReputation,
  tc.UserCreationDate AS ContributorCreationDate,
  pa.Title AS PostTitle,
  pa.PostTypeName,
  pa.PostCreationDate,
  pa.Score AS PostScore,
  pa.ViewCount AS PostViewCount,
  pa.AnswerCount AS PostAnswerCount,
  pa.CommentCountPerPost,
  pa.FavoriteCount AS PostFavoriteCount,
  pa.IsClosed,
  pa.DaysToClose,
  pa.IsCommunityOwned,
  pa.TotalUpvotes,
  pa.TagName,
  CASE
    WHEN pa.PostTypeId = 1 THEN 'Question'
    WHEN pa.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS TypeCategory,
  CASE
    WHEN pa.IsClosed = 1 THEN 'Closed'
    WHEN pa.IsCommunityOwned = 1 THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  pa.TotalUpvotes * 1.0 / NULLIF(pa.ViewCount, 0) AS UpvoteToViewRatio,
  COALESCE(pa.AnswerCount, 0) + COALESCE(pa.CommentCountPerPost, 0) AS EngagementCount,
  DATE_PART('year', pa.PostCreationDate) AS PostYear,
  CASE
    WHEN EXTRACT(HOUR FROM pa.PostCreationDate) BETWEEN 6 AND 11 THEN 'Morning'
    WHEN EXTRACT(HOUR FROM pa.PostCreationDate) BETWEEN 12 AND 17 THEN 'Afternoon'
    WHEN EXTRACT(HOUR FROM pa.PostCreationDate) BETWEEN 18 AND 23 THEN 'Evening'
    ELSE 'Night'
  END AS PostHourOfDay
FROM TopContributors tc
JOIN PostAnalysis pa
  ON tc.UserId = pa.OwnerUserId
WHERE
  tc.RepRank <= 100
  AND pa.Score > 5
  AND pa.PostTypeName IN ('Question', 'Answer')
  AND pa.TagName IS NOT NULL
  AND pa.PostCreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
UNION ALL
SELECT
  tc.DisplayName AS TopContributorName,
  tc.Reputation AS ContributorReputation,
  tc.UserCreationDate AS ContributorCreationDate,
  pa.Title AS PostTitle,
  pa.PostTypeName,
  pa.PostCreationDate,
  pa.Score AS PostScore,
  pa.ViewCount AS PostViewCount,
  pa.AnswerCount AS PostAnswerCount,
  pa.CommentCountPerPost,
  pa.FavoriteCount AS PostFavoriteCount,
  pa.IsClosed,
  pa.DaysToClose,
  pa.IsCommunityOwned,
  pa.TotalUpvotes,
  pa.TagName,
  CASE
    WHEN pa.PostTypeId = 1 THEN 'Question'
    WHEN pa.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS TypeCategory,
  CASE
    WHEN pa.IsClosed = 1 THEN 'Closed'
    WHEN pa.IsCommunityOwned = 1 THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  pa.TotalUpvotes * 1.0 / NULLIF(pa.ViewCount, 0) AS UpvoteToViewRatio,
  COALESCE(pa.AnswerCount, 0) + COALESCE(pa.CommentCountPerPost, 0) AS EngagementCount,
  DATE_PART('year', pa.PostCreationDate) AS PostYear,
  CASE
    WHEN EXTRACT(HOUR FROM pa.PostCreationDate) BETWEEN 6 AND 11 THEN 'Morning'
    WHEN EXTRACT(HOUR FROM pa.PostCreationDate) BETWEEN 12 AND 17 THEN 'Afternoon'
    WHEN EXTRACT(HOUR FROM pa.PostCreationDate) BETWEEN 18 AND 23 THEN 'Evening'
    ELSE 'Night'
  END AS PostHourOfDay
FROM TopContributors tc
JOIN PostAnalysis pa
  ON tc.UserId = pa.OwnerUserId
WHERE
  tc.RepRank <= 100
  AND pa.Score < 0
  AND pa.PostTypeName = 'Question'
  AND pa.TagName IS NOT NULL
  AND pa.PostCreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31';