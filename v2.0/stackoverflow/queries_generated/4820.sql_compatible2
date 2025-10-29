WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  PostEditDetails AS (
    SELECT
      rph.PostId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.CreationDate ELSE NULL END) AS LastTitleEditDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.CreationDate ELSE NULL END) AS LastBodyEditDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.CreationDate ELSE NULL END) AS LastTagsEditDate,
      COUNT(CASE WHEN rph.PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS TitleEditCount,
      COUNT(CASE WHEN rph.PostHistoryTypeId = 5 THEN 1 ELSE NULL END) AS BodyEditCount,
      COUNT(CASE WHEN rph.PostHistoryTypeId = 6 THEN 1 ELSE NULL END) AS TagsEditCount,
      SUM(CASE WHEN rph.rn = 1 THEN 1 ELSE 0 END) AS IsMostRecentEdit
    FROM
      RankedPostHistory rph
    GROUP BY
      rph.PostId
  ),
  UserPostInteraction AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
      COUNT(DISTINCT c.Id) AS TotalCommentsMade,
      COUNT(DISTINCT v.Id) AS TotalVotesCast,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesCast,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesCast
    FROM
      Posts p
    LEFT JOIN
      Comments c
      ON p.OwnerUserId = c.UserId
    LEFT JOIN
      Votes v
      ON p.OwnerUserId = v.UserId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  ClosedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.ClosedDate,
      crt.Name AS CloseReason,
      COUNT(DISTINCT ph.Id) AS CloseVoteCount
    FROM
      Posts p
    JOIN
      PostHistory ph
      ON p.Id = ph.PostId
    JOIN
      CloseReasonTypes crt
      ON CASE
           WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER)
           ELSE NULL
         END = crt.Id
    WHERE
      p.PostTypeId = 1
      AND ph.PostHistoryTypeId = 10
      AND ph.Comment IS NOT NULL
      AND ph.Comment ~ '^[0-9]+$'
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.ClosedDate,
      crt.Name
  ),
  HotNetworkQuestions AS (
    SELECT
      ph.PostId,
      ph.CreationDate AS HotDate
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId = 52
  )
SELECT
  COALESCE(u.DisplayName, 'Unknown User') AS UserName,
  COALESCE(u.Reputation, 0) AS UserReputation,
  COALESCE(up.TotalPostsOwned, 0) AS UserTotalPosts,
  COALESCE(up.TotalQuestionsOwned, 0) AS UserTotalQuestions,
  COALESCE(up.TotalAnswersOwned, 0) AS UserTotalAnswers,
  COALESCE(up.TotalCommentsMade, 0) AS UserTotalComments,
  COALESCE(up.TotalVotesCast, 0) AS UserTotalVotes,
  COALESCE(up.TotalUpVotesCast, 0) AS UserTotalUpVotes,
  COALESCE(up.TotalDownVotesCast, 0) AS UserTotalDownVotes,
  COALESCE(ped.TitleEditCount, 0) AS UserTitleEdits,
  COALESCE(ped.BodyEditCount, 0) AS UserBodyEdits,
  COALESCE(ped.TagsEditCount, 0) AS UserTagsEdits,
  COALESCE(cq.CloseReason, 'Not Closed') AS LastCloseReason,
  COALESCE(cq.CloseVoteCount, 0) AS UserCloseVoteCount,
  CASE
    WHEN hnq.HotDate IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS WasHotNetworkQuestion,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteCategory,
  CASE
    WHEN u.AboutMe IS NULL OR TRIM(u.AboutMe) = '' THEN 'No Bio'
    WHEN LENGTH(u.AboutMe) > 500 THEN 'Long Bio'
    ELSE 'Short Bio'
  END AS BioLengthCategory,
  (
    SELECT
      COUNT(*)
    FROM
      Badges b
    WHERE
      b.UserId = u.Id
      AND b.Class = 1
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges b
    WHERE
      b.UserId = u.Id
      AND b.Class = 2
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges b
    WHERE
      b.UserId = u.Id
      AND b.Class = 3
  ) AS BronzeBadges,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccessDate,
  CASE
    WHEN CAST((EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400) AS INTEGER) > 365 THEN 'Veteran'
    ELSE 'Newer'
  END AS UserTenureCategory,
  COALESCE(ped.IsMostRecentEdit, 0) AS UserIsMostRecentEditor
FROM
  Users u
LEFT JOIN
  UserPostInteraction up
  ON u.Id = up.OwnerUserId
LEFT JOIN
  PostEditDetails ped
  ON u.Id = ped.PostId
LEFT JOIN
  ClosedQuestions cq
  ON u.Id = cq.OwnerUserId
LEFT JOIN
  HotNetworkQuestions hnq
  ON u.Id = hnq.PostId
WHERE
  u.Id > 1000
  AND u.Reputation > 500
  AND u.DownVotes < u.UpVotes * 0.1
  AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%'
  AND EXISTS (
    SELECT
      1
    FROM
      Posts p2
    WHERE
      p2.OwnerUserId = u.Id
      AND p2.PostTypeId = 1
      AND p2.AnswerCount > 5
      AND p2.Score > 10
  )
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  up.TotalPostsOwned,
  up.TotalQuestionsOwned,
  up.TotalAnswersOwned,
  up.TotalCommentsMade,
  up.TotalVotesCast,
  up.TotalUpVotesCast,
  up.TotalDownVotesCast,
  ped.TitleEditCount,
  ped.BodyEditCount,
  ped.TagsEditCount,
  ped.IsMostRecentEdit,
  cq.CloseReason,
  cq.CloseVoteCount,
  hnq.HotDate,
  u.WebsiteUrl,
  u.AboutMe,
  u.CreationDate,
  u.LastAccessDate
ORDER BY
  UserReputation DESC,
  UserTotalPosts DESC
LIMIT 100;