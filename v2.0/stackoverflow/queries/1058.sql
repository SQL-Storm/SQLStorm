WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS ReputationRank,
        (u.Reputation + u.UpVotes * 2 - u.DownVotes * 0.5) * (1.0 + EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 31536000.0 / 100.0) AS UserEngagementScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN b.Name LIKE '%Analyst%' OR b.Name LIKE '%Contributor%' THEN 1 ELSE 0 END) AS IsSpecializedUser
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.Views > 50 AND u.DisplayName IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
PostEngagementDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.OwnerUserId AS QuestionOwnerId,
        q.Tags,
        q.AnswerCount,
        a.Id AS AcceptedAnswerId,
        a.CreationDate AS AcceptedAnswerCreationDate,
        a.Score AS AcceptedAnswerScore,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 AS TimeToAcceptAnswerHours,
        AVG(q.Score) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgQuestionScoreByOwner,
        COALESCE(array_length(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><'), 1), 0) AS NumberOfTags,
        SUM(CASE WHEN pl_dup.LinkTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY q.Id) AS DuplicateLinkCount,
        SUM(CASE WHEN pl_linked.LinkTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY q.Id) AS LinkedFromOtherPostsCount
    FROM Posts q
    INNER JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN PostLinks pl_dup ON q.Id = pl_dup.PostId AND pl_dup.LinkTypeId = 3
    LEFT JOIN PostLinks pl_linked ON q.Id = pl_linked.RelatedPostId AND pl_linked.LinkTypeId = 1
    WHERE q.PostTypeId = 1
      AND q.Score > 50
      AND q.ViewCount > 1000
      AND q.Title IS NOT NULL
      AND q.AcceptedAnswerId IS NOT NULL
),
PostHistoryAudit AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastHistoryDate,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(COALESCE(regexp_replace(ph.Comment, '^([^0-9]*)([0-9]+).*$', '\2'), '0') AS INTEGER) ELSE NULL END) AS LastCloseReasonId,
        COALESCE(MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END), TIMESTAMP '1900-01-01 00:00:00') AS LastClosedDate,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - prev_CreationDate))) AS AvgEditIntervalSeconds
    FROM (
        SELECT
            ph.*,
            LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS prev_CreationDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13)
    ) ph
    GROUP BY ph.PostId
),
CorrelatedUserInteraction AS (
    SELECT
        uas.UserId,
        COUNT(DISTINCT p.Id) AS UserEditedHighScorePostsCount
    FROM UserActivitySummary uas
    JOIN Posts p ON uas.UserId = p.LastEditorUserId
    WHERE p.Score > 200
      AND p.PostTypeId IN (1, 2)
      AND p.OwnerUserId <> uas.UserId
    GROUP BY uas.UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.ReputationRank,
    ua.UserEngagementScore,
    ua.TotalBadges,
    ua.GoldBadges,
    ua.IsSpecializedUser,
    ped.QuestionId,
    ped.QuestionTitle,
    ped.QuestionScore,
    ped.QuestionViewCount,
    ped.NumberOfTags,
    ped.TimeToAcceptAnswerHours,
    ped.RunningAvgQuestionScoreByOwner,
    ped.DuplicateLinkCount,
    ped.LinkedFromOtherPostsCount,
    pha.TotalHistoryEvents,
    pha.EditCount,
    pha.CloseEventCount,
    pha.LastCloseReasonId,
    pha.LastClosedDate,
    pha.AvgEditIntervalSeconds,
    ci.UserEditedHighScorePostsCount,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = ped.QuestionId AND c.Score > 5) AS HighScoreCommentCount,
    COALESCE(
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = ped.QuestionId AND v.VoteTypeId = 2),
        ped.QuestionCreationDate
    ) AS LastUpvoteOrQuestionDate,
    CASE
        WHEN ped.TimeToAcceptAnswerHours IS NULL THEN 'No Acceptance Data'
        WHEN ped.TimeToAcceptAnswerHours < 24 THEN 'Fast Accepted (<1 day)'
        WHEN ped.TimeToAcceptAnswerHours BETWEEN 24 AND 168 THEN 'Moderately Accepted (1 day - 1 week)'
        WHEN ped.TimeToAcceptAnswerHours > 168 THEN 'Slow Accepted (>1 week)'
        ELSE 'Undefined'
    END AS AcceptanceSpeedCategory,
    ped.QuestionScore / NULLIF(ped.QuestionViewCount, 0) AS ScorePerViewRatio,
    (SELECT AVG(inner_ped.QuestionScore) FROM PostEngagementDetails inner_ped WHERE inner_ped.QuestionOwnerId = ua.UserId) AS AvgQuestionScoreForOwner
FROM UserActivitySummary ua
INNER JOIN PostEngagementDetails ped ON ua.UserId = ped.QuestionOwnerId
LEFT JOIN PostHistoryAudit pha ON ped.QuestionId = pha.PostId
LEFT JOIN CorrelatedUserInteraction ci ON ua.UserId = ci.UserId
WHERE ua.ReputationRank <= 1000
  AND ped.NumberOfTags >= 3
  AND (ped.QuestionTitle LIKE '%SQL%' OR ped.QuestionTitle LIKE '%database%' OR ped.Tags LIKE '%<postgresql>%' OR ped.Tags LIKE '%<sql-server>%')
  AND (pha.EditCount > 1 OR pha.CloseEventCount > 0 OR pha.AvgEditIntervalSeconds < 3600)
  AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_inner
        WHERE ph_inner.PostId = ped.QuestionId
          AND ph_inner.PostHistoryTypeId = 12
    )
ORDER BY ua.UserEngagementScore DESC, ped.RunningAvgQuestionScoreByOwner DESC, pha.LastHistoryDate DESC, ped.TimeToAcceptAnswerHours ASC
LIMIT 1000;