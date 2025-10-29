-- {"query": "1154.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3033} 

WITH UserPostSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount, 0) ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCount,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS EarliestGoldBadgeDate,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteInfluence AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesCasted,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesCasted,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS TotalAcceptedAnswersVoted
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserTagContributions AS (
    SELECT
        u.Id AS UserId,
        TRIM(REPLACE(REPLACE(LOWER(unnested_tags.tag_name), '&amp;', '&'), '&lt;', '<')) AS TagName,
        COUNT(p.Id) AS TagPostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS unnested_tags(tag_name)
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY u.Id, unnested_tags.tag_name
),
TopUserTags AS (
    SELECT
        utc.UserId,
        STRING_AGG(utc.TagName || ' (' || utc.TagPostCount || ')', ', ' ORDER BY utc.TagPostCount DESC) AS TopTagsSummary,
        MAX(utc.TagPostCount) AS MaxPostsInSingleTag
    FROM UserTagContributions utc
    GROUP BY utc.UserId
),
ActiveCommunityMembers AS (
    SELECT u.Id AS UserId
    FROM Users u
    LEFT JOIN UserPostSummary ups ON u.Id = ups.UserId
    WHERE COALESCE(ups.TotalPosts, 0) > 50 AND COALESCE(ups.TotalQuestions, 0) > 5
    UNION
    SELECT u.Id AS UserId
    FROM Users u
    LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
    WHERE COALESCE(uca.TotalComments, 0) > 100 AND u.Reputation > 500
),
UserModerationHistory AS (
    SELECT
        ph.UserId,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS TotalDeletedPosts,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN 'User has deleted posts' ELSE NULL END) AS UserDeletionActivityIndicator,
        MAX(ph.CreationDate) AS LastModerationActionDate
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY ph.UserId
),
UserPostEditActivity AS (
    SELECT
        p.LastEditorUserId AS UserId,
        COUNT(p.Id) AS TotalPostsEdited,
        MAX(p.LastEditDate) AS LastEditDateByThisUser
    FROM Posts p
    WHERE p.LastEditorUserId IS NOT NULL
    GROUP BY p.LastEditorUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.WebsiteUrl,
    u.Location,
    COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 200), 'No "About Me" information provided.') AS ShortAboutMeSnippet,
    u.Views AS ProfileViews,
    u.UpVotes AS TotalReceivedUpVotes,
    u.DownVotes AS TotalReceivedDownVotes,
    (EXTRACT(EPOCH FROM (NOW() - u.LastAccessDate)) / 3600)::numeric AS HoursSinceLastAccess,
    COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ups.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(ups.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(ups.AvgPostScore, 0.0) AS UserAvgPostScore,
    COALESCE(ups.TotalQuestionViews, 0) AS UserTotalQuestionViews,
    COALESCE(ups.TotalFavoriteCount, 0) AS UserTotalFavoritePosts,
    COALESCE(uca.TotalComments, 0) AS UserTotalComments,
    COALESCE(uca.AvgCommentScore, 0.0) AS UserAvgCommentScore,
    COALESCE(ubs.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS UserBronzeBadges,
    CASE
        WHEN ubs.EarliestGoldBadgeDate IS NOT NULL THEN (EXTRACT(DAY FROM (ubs.EarliestGoldBadgeDate - u.CreationDate)) / 365.25)::numeric
        ELSE NULL
    END AS YearsToFirstGoldBadge,
    COALESCE(uvi.TotalUpVotesCasted, 0) AS UserCastedUpVotes,
    COALESCE(uvi.TotalDownVotesCasted, 0) AS UserCastedDownVotes,
    COALESCE(NULLIF(u.UpVotes, 0)::numeric / NULLIF(u.DownVotes, 0), 0.0) AS ReceivedUpDownVoteRatio,
    COALESCE(NULLIF(COALESCE(uvi.TotalUpVotesCasted, 0), 0)::numeric / NULLIF(COALESCE(uvi.TotalDownVotesCasted, 0), 0), 0.0) AS CastedUpDownVoteRatio,
    CASE
        WHEN u.Reputation >= 200000 AND COALESCE(ubs.GoldBadges, 0) >= 5 THEN 'Legendary Grandmaster'
        WHEN u.Reputation >= 50000 AND COALESCE(ubs.GoldBadges, 0) >= 1 THEN 'Esteemed Guru'
        WHEN u.Reputation >= 10000 AND COALESCE(ups.TotalPosts, 0) >= 100 THEN 'Prodigious Contributor'
        WHEN u.Reputation >= 1000 THEN 'Active Member'
        ELSE 'Novice'
    END AS UserEngagementTier,
    COALESCE(tut.TopTagsSummary, 'No Specific Tags Identified') AS TopUserTagsSummary,
    COALESCE(tut.MaxPostsInSingleTag, 0) AS MaxPostsInTopTag,
    (
        SELECT COALESCE(AVG(ans.Score), 0.0)
        FROM Posts ans
        JOIN Posts q_parent ON ans.ParentId = q_parent.Id
        WHERE ans.OwnerUserId = u.Id
          AND ans.PostTypeId = 2
          AND q_parent.OwnerUserId = u.Id
    ) AS AvgScoreOfSelfAnswersToOwnQuestions,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS GlobalReputationRank,
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RankInLocation,
    AVG(u.Reputation) OVER (PARTITION BY DATE_TRUNC('year', u.CreationDate)) AS AvgReputationForCreationYear,
    COALESCE(LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate), 0) AS PreviousUserReputationByCreationDate,
    COALESCE(umh.TotalClosedPosts, 0) AS UserTotalClosedPosts,
    COALESCE(umh.TotalDeletedPosts, 0) AS UserTotalDeletedPosts,
    COALESCE(umh.UserDeletionActivityIndicator, 'No historical deletions') AS UserDeletionStatus,
    COALESCE(upea.TotalPostsEdited, 0) AS UserTotalPostsEdited,
    COALESCE(upea.LastEditDateByThisUser, u.CreationDate) AS LastPostEditActionDate,
    COUNT(DISTINCT acm.UserId) OVER () AS TotalDistinctActiveCommunityMembers,
    CASE WHEN acm.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS IsHighlyActiveCommunityMember,
    COALESCE(
        (SELECT p.Title FROM Posts p WHERE p.LastEditorUserId = u.Id AND p.PostTypeId = 1 ORDER BY p.LastEditDate DESC LIMIT 1),
        'N/A'
    ) AS MostRecentEditedQuestionTitleByThisUser,
    CASE
        WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 250 THEN 'Long AboutMe: ' || SUBSTRING(u.AboutMe FROM 1 FOR 50) || '...' || SUBSTRING(u.AboutMe FROM LENGTH(u.AboutMe) - 50 FOR 50)
        WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 0 THEN 'Short AboutMe: ' || u.AboutMe
        ELSE 'No AboutMe provided'
    END AS AboutMeSummaryExtended,
    EXTRACT(DAY FROM (NOW() - COALESCE(ups.LastPostActivityDate, uca.LastCommentDate, u.LastAccessDate, u.CreationDate))) AS DaysSinceLastMajorActivity

FROM Users u
LEFT JOIN UserPostSummary ups ON u.Id = ups.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserVoteInfluence uvi ON u.Id = uvi.UserId
LEFT JOIN TopUserTags tut ON u.Id = tut.UserId
LEFT JOIN ActiveCommunityMembers acm ON u.Id = acm.UserId
LEFT JOIN UserModerationHistory umh ON u.Id = umh.UserId
LEFT JOIN UserPostEditActivity upea ON u.Id = upea.UserId
WHERE u.Reputation > 500
  AND u.LastAccessDate IS NOT NULL
  AND (u.Location LIKE '%Canada%' OR u.Location LIKE '%United States%' OR u.Location LIKE '%UK%' OR u.Location IS NULL)
  AND (COALESCE(ups.TotalPosts, 0) > 10 OR COALESCE(ubs.TotalBadges, 0) > 5)
  AND (u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 20)
  AND (COALESCE(ups.QuestionsWithAcceptedAnswer, 0)::numeric / NULLIF(COALESCE(ups.TotalQuestions, 0), 0) >= 0.25 OR COALESCE(ups.TotalQuestions, 0) = 0)
ORDER BY GlobalReputationRank ASC, UserTotalPosts DESC
LIMIT 500;
