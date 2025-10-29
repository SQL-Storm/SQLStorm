WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViewCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS MaxQuestionViewCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AcceptedAnswerCount,
        AVG(LENGTH(p.Body)) AS AvgPostBodyLength,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN (SELECT q.Score FROM Posts q WHERE q.Id = p.ParentId) ELSE 0 END), 0) AS TotalParentQuestionScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId AND p.OwnerUserId = c.UserId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserHistoryAggregates AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        MAX(ph.CreationDate) AS LastHistoryActivity,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId ELSE NULL END) AS UniquePostsEdited,
        COUNT(CASE WHEN LOWER(ph.Comment) LIKE '%revert%' OR LOWER(ph.Comment) LIKE '%undo%' THEN 1 ELSE 0 END) AS RollbackRelatedHistory
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
EliteUsersByReputationAndAcceptedAnswers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        'HighReputationWithSelfAcceptedAnswer' AS EliteCriteria,
        NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationTier
    FROM Users u
    JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.OwnerUserId = u.Id
    WHERE q.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND u.Reputation > 7500
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
EliteUsersByBadgesAndHighEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        'ManyGoldBadgesAndHighEngagement' AS EliteCriteria,
        NTILE(5) OVER (ORDER BY u.UpVotes DESC) AS UpVotesTier,
        u.UpVotes
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
    WHERE b.Class = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes
    HAVING COUNT(b.Id) >= 5
       AND u.UpVotes > 2000
       AND COALESCE(SUM(ups.TotalCommentsMade), 0) > 50
),
CombinedEliteUsers AS (
    SELECT DISTINCT UserId, DisplayName, Reputation, EliteCriteria, ReputationTier AS Tier
    FROM EliteUsersByReputationAndAcceptedAnswers
    UNION ALL
    SELECT DISTINCT UserId, DisplayName, Reputation, EliteCriteria, UpVotesTier AS Tier
    FROM EliteUsersByBadgesAndHighEngagement
),
TrendingTagsRanking AS (
    SELECT
        TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        COALESCE(AVG(p.AnswerCount), 0) AS AvgAnswerCount,
        RANK() OVER (ORDER BY AVG(p.Score) DESC, COUNT(DISTINCT p.Id) DESC, COALESCE(AVG(p.AnswerCount), 0) DESC) AS TagScoreRank
    FROM Posts p,
         LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName) t
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '9 months'
      AND p.Score > 10
      AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY TagName
    HAVING COUNT(DISTINCT p.Id) >= 20
),
UserTagActivity AS (
    SELECT
        u.Id AS UserId,
        ttr.TagName,
        COUNT(DISTINCT p.Id) AS PostsInTag,
        COALESCE(SUM(p.Score), 0) AS ScoreInTag,
        MAX(p.CreationDate) AS LastPostInTag
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId,
         LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName) PostTag
    JOIN TrendingTagsRanking ttr ON PostTag.TagName = ttr.TagName
    WHERE ttr.TagScoreRank <= 10
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, ttr.TagName
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.WebsiteUrl,
    u.Location,
    u.Views AS UserProfileViews,
    u.UpVotes AS UserTotalUpVotes,
    u.DownVotes AS UserTotalDownVotes,
    COALESCE(ups.TotalPosts, 0) AS TotalUserPosts,
    COALESCE(ups.QuestionCount, 0) AS UserQuestionCount,
    COALESCE(ups.AnswerCount, 0) AS UserAnswerCount,
    COALESCE(ups.TotalPostScore, 0) AS UserTotalPostScore,
    COALESCE(ups.TotalParentQuestionScore, 0) AS UserTotalParentQuestionScore,
    COALESCE(ups.TotalViewCount, 0) AS UserTotalPostViewCount,
    COALESCE(ups.AvgQuestionScore, 0.0) AS UserAvgQuestionScore,
    COALESCE(ups.MaxQuestionViewCount, 0) AS UserMaxQuestionViewCount,
    COALESCE(ups.AvgPostBodyLength, 0.0) AS UserAvgPostBodyLength,
    COALESCE(uha.EditCount, 0) AS UserEditCount,
    COALESCE(uha.CloseVoteCount, 0) AS UserCloseVoteCount,
    COALESCE(uha.UniquePostsEdited, 0) AS UniquePostsEditedByUser,
    COALESCE(uha.RollbackRelatedHistory, 0) AS UserRollbackHistoryCount,
    COALESCE(ceu.EliteCriteria, 'NotElite') AS EliteUserStatus,
    ceu.Tier AS EliteUserTier,
    CAST(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS INTEGER) AS AccountAgeDays,
    (
        SELECT MAX(ans.Score)
        FROM Posts ans
        WHERE ans.OwnerUserId = u.Id
          AND ans.PostTypeId = 2
          AND ans.ParentId IS NOT NULL
          AND (SELECT q.OwnerUserId FROM Posts q WHERE q.Id = ans.ParentId) != u.Id
          AND ans.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    ) AS MaxScoreOnOtherUsersQuestion,
    COALESCE(
        SUBSTRING(u.WebsiteUrl,
                  CASE WHEN POSITION('//' IN u.WebsiteUrl) > 0 THEN POSITION('//' IN u.WebsiteUrl) + 2 ELSE 1 END,
                  CASE WHEN POSITION('/' IN SUBSTRING(u.WebsiteUrl, CASE WHEN POSITION('//' IN u.WebsiteUrl) > 0 THEN POSITION('//' IN u.WebsiteUrl) + 2 ELSE 1 END)) > 0
                       THEN POSITION('/' IN SUBSTRING(u.WebsiteUrl, CASE WHEN POSITION('//' IN u.WebsiteUrl) > 0 THEN POSITION('//' IN u.WebsiteUrl) + 2 ELSE 1 END)) - 1
                       ELSE LENGTH(SUBSTRING(u.WebsiteUrl, CASE WHEN POSITION('//' IN u.WebsiteUrl) > 0 THEN POSITION('//' IN u.WebsiteUrl) + 2 ELSE 1 END))
                  END),
        'NoWebsiteProvided'
    ) AS WebsiteDomain,
    AVG(COALESCE(ups.TotalPostScore, 0)) OVER (PARTITION BY (u.Reputation / 500)) AS AvgPostScoreInRepBand,
    CASE
        WHEN COALESCE(ups.TotalPosts, 0) > 0 THEN CAST(COALESCE(uha.UniquePostsEdited, 0) AS NUMERIC) / ups.TotalPosts
        ELSE 0.0
    END AS UniqueEditRatio,
    (LOWER(u.Location) LIKE '%london%' OR LOWER(u.Location) LIKE '%ny%' OR LOWER(u.AboutMe) LIKE '%python%' OR LOWER(u.AboutMe) LIKE '%java%' OR LOWER(u.AboutMe) LIKE '%sql%') AS IsTechHubUserOrDeveloper,
    EXISTS (
        SELECT 1
        FROM UserTagActivity uta
        WHERE uta.UserId = u.Id
          AND uta.ScoreInTag > 5
          AND uta.LastPostInTag >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
        LIMIT 1
    ) AS ActiveInTrendingTag,
    ROW_NUMBER() OVER (PARTITION BY SUBSTRING(u.Location, 1, POSITION(',' IN (u.Location || ',') ) - 1) ORDER BY u.Reputation DESC) AS RankInLocationRegion
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserHistoryAggregates uha ON u.Id = uha.UserId
LEFT JOIN CombinedEliteUsers ceu ON u.Id = ceu.UserId
WHERE
    u.Reputation > 1000
    AND u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
    AND COALESCE(ups.TotalPosts, 0) > 10
    AND (u.Location IS NOT NULL AND u.Location <> '' AND u.Location NOT LIKE '%(deleted user)%')
    AND u.DisplayName IS NOT NULL AND LENGTH(u.DisplayName) > 2
    AND (u.CreationDate <= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' OR ceu.UserId IS NOT NULL)
ORDER BY
    u.Reputation DESC,
    UserTotalPostScore DESC,
    u.LastAccessDate DESC
LIMIT 5000;