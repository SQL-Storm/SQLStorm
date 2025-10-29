-- {"query": "1519.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4189}
WITH UserPostActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN COALESCE(p.ViewCount, 0) ELSE 0 END) AS TotalQuestionViews,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        COUNT(DISTINCT p.AcceptedAnswerId) FILTER (WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswersGivenCount,
        SUM(CASE WHEN p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months' THEN 1 ELSE 0 END) AS RecentPostsCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT c.PostId) AS UniquePostsCommented
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END) AS DownVotesCast,
        COUNT(v.Id) AS TotalVotesCast,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'Favorite') THEN 1 ELSE 0 END) AS FavoritesMade
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserPostVoteReceived AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'Favorite') THEN 1 ELSE 0 END) AS FavoritesReceived
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND v.VoteTypeId IN (
        (SELECT Id FROM VoteTypes WHERE Name = 'UpMod'),
        (SELECT Id FROM VoteTypes WHERE Name = 'DownMod'),
        (SELECT Id FROM VoteTypes WHERE Name = 'Favorite')
    )
    GROUP BY p.OwnerUserId
),
UserBadgeAwards AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE b.Class WHEN 1 THEN 5 WHEN 2 THEN 2 WHEN 3 THEN 1 ELSE 0 END) AS BadgeValueScore,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadgesCount
    FROM Badges b
    GROUP BY b.UserId
),
UserEditHistory AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEdited,
        COUNT(ph.Id) AS TotalEdits,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    AND ph.PostHistoryTypeId IN (
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Title'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Body'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Tags'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Rollback Title'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Rollback Body'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Rollback Tags')
    )
    GROUP BY ph.UserId
),
PostTaggingFrequency AS (
    SELECT
        p.OwnerUserId AS UserId,
        LOWER(t.tag) AS TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgScorePerTag
    FROM Posts p,
         LATERAL (
           SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')) AS tag
         ) t
    WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
      AND p.Tags IS NOT NULL
      AND p.OwnerUserId IS NOT NULL
      AND CHAR_LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId, LOWER(t.tag)
    HAVING COUNT(DISTINCT p.Id) >= 5
),
TopTagsPerUser AS (
    SELECT
        UserId,
        TagName,
        PostsWithTag,
        AvgScorePerTag,
        ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY PostsWithTag DESC, AvgScorePerTag DESC, TagName ASC) as TagRank
    FROM PostTaggingFrequency
),
UserMostFrequentTag AS (
    SELECT UserId, TagName AS MostFrequentTag, PostsWithTag AS MostFrequentTagPosts, AvgScorePerTag AS MostFrequentTagAvgScore
    FROM TopTagsPerUser
    WHERE TagRank = 1
),
ClosedPostAnalysis AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalClosedPostsAsOwner,
        SUM(CASE WHEN ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') THEN 1 ELSE 0 END) AS ClosedByHistoryCount,
        MAX(ph.CreationDate) AS LastClosedDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IS NOT NULL AND ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
    GROUP BY p.OwnerUserId
),
RelatedPostEngagement AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalRelatedPosts,
        SUM(CASE WHEN pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked') THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate') THEN 1 ELSE 0 END) AS DuplicatePostsCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserContentLicenseAnalysis AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.ContentLicense) AS UniquePostLicenses,
        COUNT(DISTINCT c.ContentLicense) AS UniqueCommentLicenses,
        MAX(p.ContentLicense) AS DominantPostLicense,
        MAX(c.ContentLicense) AS DominantCommentLicense
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId AND p.OwnerUserId = c.UserId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
ModerationActivity AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS ModerationActionCount,
        MAX(ph.CreationDate) AS LastModerationAction
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Locked'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Unlocked'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Question Protected'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Question Unprotected')
    )
    GROUP BY ph.UserId
)
SELECT
    u.Id AS UserID,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    u.Views AS UserProfileViews,
    COALESCE(u.UpVotes, 0) AS TotalUpVotesGiven,
    COALESCE(u.DownVotes, 0) AS TotalDownVotesGiven,
    COALESCE(upa.TotalPosts, 0) AS TotalPosts,
    COALESCE(upa.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(upa.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(upa.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(upa.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(upa.RecentPostsCount, 0) AS RecentPostsCount,
    COALESCE(uca.TotalComments, 0) AS TotalComments,
    COALESCE(uca.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(upr.UpVotesReceived, 0) AS UpVotesReceivedOnPosts,
    COALESCE(upr.DownVotesReceived, 0) AS DownVotesReceivedOnPosts,
    COALESCE(upr.FavoritesReceived, 0) AS FavoritesReceivedOnPosts,
    COALESCE(usb.TotalBadges, 0) AS TotalBadges,
    COALESCE(usb.BadgeValueScore, 0) AS TotalBadgeValue,
    COALESCE(usb.GoldBadgesCount, 0) AS GoldBadgesCount,
    COALESCE(ueh.UniquePostsEdited, 0) AS UniquePostsEdited,
    COALESCE(ueh.TotalEdits, 0) AS TotalEdits,
    umft.MostFrequentTag,
    umft.MostFrequentTagPosts,
    COALESCE(cpa.TotalClosedPostsAsOwner, 0) AS TotalClosedPostsAsOwner,
    COALESCE(m_act.ModerationActionCount, 0) AS UserModerationActions,
    CAST(COALESCE(upa.TotalPostScore, 0) AS NUMERIC) / NULLIF(COALESCE(upa.TotalPosts, 0), 0) AS AvgPostScorePerPost,
    CAST(COALESCE(upr.UpVotesReceived, 0) AS NUMERIC) / NULLIF(COALESCE(upr.UpVotesReceived, 0) + COALESCE(upr.DownVotesReceived, 0), 0) AS PostUpvoteRatio,
    EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24 * 365.25) AS YearsActiveApprox,
    COALESCE(DATE_PART('day', upa.LastPostDate - upa.FirstPostDate), 0) AS DaysBetweenFirstAndLastPost,
    CASE
        WHEN u.Reputation >= 100000 AND COALESCE(usb.GoldBadgesCount, 0) >= 10 THEN 'Titan'
        WHEN u.Reputation >= 50000 AND COALESCE(upa.TotalQuestions, 0) >= 50 AND COALESCE(upa.AcceptedAnswersGivenCount, 0) >= 10 THEN 'Answer King'
        WHEN u.Reputation >= 10000 AND COALESCE(ueh.TotalEdits, 0) >= 50 AND COALESCE(upa.TotalPosts, 0) >= 200 THEN 'Prolific Editor'
        WHEN u.Reputation >= 2000 AND COALESCE(uca.TotalComments, 0) >= 100 THEN 'Community Voice'
        ELSE 'Contributor'
    END AS UserEngagementTier,
    REPLACE(
      -- portable capitalization: capitalize first letter of each word by lowercasing and using regexp_replace to capitalize word starts
      REGEXP_REPLACE(
        LOWER(COALESCE(NULLIF(REGEXP_SUBSTR(u.Location, '^[^0-9,]+'), ''), 'Earth')),
        '(^|\s)([a-z])',
        '\1' || UPPER('\2'),
        'g'
      ),
      ' ',
      ''
    ) AS LocationCleanedString,
    UPPER(SUBSTRING(COALESCE(u.DisplayName, 'UNKNOWN') FROM 1 FOR 1)) || LPAD(CAST(u.AccountId AS VARCHAR), 9, '0') AS UserAccountIdentifier,
    COALESCE(REPLACE(u.WebsiteUrl, 'http://', ''), REPLACE(u.WebsiteUrl, 'https://', '')) AS WebsiteUrlStripped,
    (SELECT AVG(sub_p.Score) FROM Posts sub_p WHERE sub_p.OwnerUserId = u.Id AND sub_p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') AND sub_p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') AS AvgRecentAnswerScore,
    (SELECT COUNT(1) FROM Badges b_spec WHERE b_spec.UserId = u.Id AND b_spec.Name LIKE '%Analyst%') AS HasAnalystBadge,
    (SELECT ph_latest.Comment FROM PostHistory ph_latest WHERE ph_latest.PostId = (SELECT p_latest.Id FROM Posts p_latest WHERE p_latest.OwnerUserId = u.Id ORDER BY p_latest.CreationDate DESC LIMIT 1) ORDER BY ph_latest.CreationDate DESC LIMIT 1) AS LastPostHistoryComment,
    RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(upa.TotalPostScore, 0) DESC) AS OverallReputationRank,
    NTILE(10) OVER (ORDER BY COALESCE(upa.TotalQuestions, 0) DESC, COALESCE(upa.TotalAnswers, 0) DESC) AS QuestionAnswerVolumeDecile,
    LAG(u.Reputation, 1, 0) OVER (PARTITION BY COALESCE(u.Location, 'Global') ORDER BY u.Reputation DESC) AS PrevUserRepInLocation,
    DENSE_RANK() OVER (ORDER BY COALESCE(upr.UpVotesReceived, 0) DESC) AS UpvoteReceiverRank,
    AVG(COALESCE(upa.TotalPostScore, 0)) OVER (ORDER BY u.CreationDate ROWS BETWEEN 100 PRECEDING AND CURRENT ROW) AS RollingAvgPostScore,
    (u.AboutMe IS NOT NULL AND CHAR_LENGTH(u.AboutMe) > 200 AND u.AboutMe LIKE '%SQL%') AS HasDetailedSqlAboutMe,
    (u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month' AND COALESCE(upa.TotalPosts, 0) + COALESCE(uca.TotalComments, 0) > 10) AS HighlyActiveRecently,
    (COALESCE(uca.UniquePostsCommented, 0) > COALESCE(upa.TotalQuestions, 0) * 2) AS MoreCommentsThanQuestionsRatio,
    (u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' AND u.WebsiteUrl LIKE '%github.com%') AS HasGitHubProfile,
    (COALESCE(ucla.DominantPostLicense, 'UNKNOWN') = COALESCE(ucla.DominantCommentLicense, 'UNKNOWN')) AS ConsistentContentLicense,
    (SELECT MAX(t.Count) FROM Tags t WHERE t.TagName LIKE 'java%') AS MaxJavaTagCount
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
LEFT JOIN UserPostVoteReceived upr ON u.Id = upr.UserId
LEFT JOIN UserBadgeAwards usb ON u.Id = usb.UserId
LEFT JOIN UserEditHistory ueh ON u.Id = ueh.UserId
LEFT JOIN UserMostFrequentTag umft ON u.Id = umft.UserId
LEFT JOIN ClosedPostAnalysis cpa ON u.Id = cpa.UserId
LEFT JOIN ModerationActivity m_act ON u.Id = m_act.UserId
LEFT JOIN UserContentLicenseAnalysis ucla ON u.Id = ucla.UserId
WHERE u.Reputation >= 100
  AND (COALESCE(upa.TotalPosts, 0) > 0 OR COALESCE(uca.TotalComments, 0) > 0 OR COALESCE(usb.TotalBadges, 0) > 0)
  AND u.DisplayName IS NOT NULL AND u.DisplayName <> ''
  AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_deleted
        WHERE ph_deleted.UserId = u.Id
          AND ph_deleted.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Deleted')
    )
  AND (u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years' OR u.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
  AND (CHAR_LENGTH(u.AboutMe) IS NULL OR CHAR_LENGTH(u.AboutMe) < 5000)
  AND u.AccountId IS NOT NULL
ORDER BY OverallReputationRank ASC, TotalBadgeValue DESC, YearsActiveApprox DESC, UserEngagementTier DESC
LIMIT 5000;