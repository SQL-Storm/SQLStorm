-- {"query": "4302.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1905} 

WITH
  PostVoteCounts AS (
    SELECT
      PostId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
      COUNT(CASE WHEN VoteTypeId = 8 THEN 1 END) AS BountyStartCount,
      COUNT(CASE WHEN VoteTypeId = 9 THEN 1 END) AS BountyCloseCount,
      COUNT(CASE WHEN VoteTypeId = 10 THEN 1 END) AS DeletionVoteCount,
      COUNT(CASE WHEN VoteTypeId = 16 THEN 1 END) AS ApproveEditSuggestionCount
    FROM Votes
    WHERE
      VoteTypeId IN (2, 3, 8, 9, 10, 16)
    GROUP BY
      PostId
  ),
  PostCommentCounts AS (
    SELECT
      PostId,
      COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY
      PostId
  ),
  UserPostScores AS (
    SELECT
      OwnerUserId,
      SUM(Score) AS TotalScore
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  UserCommentScores AS (
    SELECT
      UserId,
      SUM(Score) AS TotalScore
    FROM Comments
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  UserBadgeCounts AS (
    SELECT
      UserId,
      COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadgeCount,
      COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadgeCount,
      COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM Badges
    GROUP BY
      UserId
  ),
  PostsWithDetails AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.ClosedDate AS PostClosedDate,
      pt.Name AS PostTypeName,
      COALESCE(pvc.UpVoteCount, 0) AS TotalUpVotes,
      COALESCE(pvc.DownVoteCount, 0) AS TotalDownVotes,
      COALESCE(pvc.BountyStartCount, 0) AS TotalBountyStarts,
      COALESCE(pvc.BountyCloseCount, 0) AS TotalBountyCloses,
      COALESCE(pvc.DeletionVoteCount, 0) AS TotalDeletionVotes,
      COALESCE(pvc.ApproveEditSuggestionCount, 0) AS TotalApproveEditSuggestions,
      COALESCE(pcc.CommentCount, 0) AS TotalComments,
      CASE
        WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0)
        ELSE 0
      END AS QuestionAnswerCount,
      CASE
        WHEN p.PostTypeId = 1 THEN CAST(STRFTIME('%Y', p.CreationDate) AS INTEGER)
        ELSE NULL
      END AS PostCreationYear,
      CASE
        WHEN p.PostTypeId = 1 THEN p.Title
        ELSE NULL
      END AS QuestionTitle,
      CASE
        WHEN p.PostTypeId = 2 THEN COALESCE(p.Score, 0) - COALESCE(pvc.DownVoteCount, 0)
        ELSE NULL
      END AS AnswerNetScore,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN JULIANDAY(p.ClosedDate) - JULIANDAY(p.CreationDate)
        ELSE NULL
      END AS DaysToClose,
      (
        SELECT
          COUNT(*)
        FROM PostLinks AS pl
        WHERE
          pl.PostId = p.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount,
      (
        SELECT
          SUM(CAST(SUBSTR(Text, INSTR(Text, ':') + 1) AS INTEGER))
        FROM PostHistory
        WHERE
          PostHistory.PostId = p.Id AND PostHistory.PostHistoryTypeId = 10 AND Text LIKE '%CloseReasonTypeId:%'
      ) AS SumOfCloseReasonIds
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN PostVoteCounts AS pvc
      ON p.Id = pvc.PostId
    LEFT JOIN PostCommentCounts AS pcc
      ON p.Id = pcc.PostId
  )
SELECT
  pwd.PostId,
  pwd.PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(ups.TotalScore, 0) AS UserPostTotalScore,
  COALESCE(ucs.TotalScore, 0) AS UserCommentTotalScore,
  COALESCE(ubc.GoldBadgeCount, 0) AS UserGoldBadges,
  COALESCE(ubc.SilverBadgeCount, 0) AS UserSilverBadges,
  COALESCE(ubc.BronzeBadgeCount, 0) AS UserBronzeBadges,
  pwd.PostCreationYear,
  pwd.PostScore,
  pwd.PostViewCount,
  pwd.PostFavoriteCount,
  pwd.PostAnswerCount,
  pwd.TotalUpVotes,
  pwd.TotalDownVotes,
  pwd.TotalBountyStarts,
  pwd.TotalBountyCloses,
  pwd.TotalDeletionVotes,
  pwd.TotalApproveEditSuggestions,
  pwd.TotalComments,
  pwd.QuestionAnswerCount,
  pwd.QuestionTitle,
  pwd.AnswerNetScore,
  pwd.DaysToClose,
  pwd.DuplicateLinkCount,
  pwd.SumOfCloseReasonIds,
  CASE
    WHEN pwd.PostTypeName = 'Question' THEN (
      SELECT
        COUNT(*)
      FROM PostHistory AS ph
      WHERE
        ph.PostId = pwd.PostId AND ph.PostHistoryTypeId = 6
    )
    ELSE NULL
  END AS TagEditCount,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = pwd.PostId AND c.UserId = pwd.OwnerUserId
  ) AS OwnerCommentsOnOwnPost,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  CASE
    WHEN pwd.PostTypeName = 'Question' THEN (
      SELECT
        SUM(ph.Id)
      FROM PostHistory AS ph
      WHERE
        ph.PostId = pwd.PostId AND ph.PostHistoryTypeId IN (4, 5)
    )
    ELSE NULL
  END AS SumOfEditHistoryIds,
  COALESCE(u.Views, 0) AS OwnerViewCount,
  COALESCE(u.UpVotes, 0) AS OwnerUpVotes,
  COALESCE(u.DownVotes, 0) AS OwnerDownVotes,
  IIF(u.WebsiteUrl IS NULL, 'No Website', 'Has Website') AS OwnerWebsiteStatus,
  SUBSTRING(u.AboutMe, 1, 50) AS OwnerAboutMeSnippet,
  COALESCE(p.LastActivityDate, pwd.PostCreationDate) AS LastPostActivityOrCreation,
  (
    SELECT
      GROUP_CONCAT(Name)
    FROM Badges
    WHERE
      UserId = pwd.OwnerUserId AND Name LIKE '%Coder%'
  ) AS CoderBadgeNames
FROM PostsWithDetails AS pwd
LEFT JOIN Users AS u
  ON pwd.OwnerUserId = u.Id
LEFT JOIN UserPostScores AS ups
  ON pwd.OwnerUserId = ups.OwnerUserId
LEFT JOIN UserCommentScores AS ucs
  ON pwd.OwnerUserId = ucs.UserId
LEFT JOIN UserBadgeCounts AS ubc
  ON pwd.OwnerUserId = ubc.UserId
LEFT JOIN Posts AS p
  ON pwd.PostId = p.Id
WHERE
  pwd.PostTypeName = 'Question'
  OR pwd.PostTypeName = 'Answer'
ORDER BY
  pwd.PostCreationYear DESC,
  pwd.PostScore DESC
LIMIT 1000;
