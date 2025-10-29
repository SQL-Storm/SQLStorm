-- {"query": "4117.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2031} 

WITH RankedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserAnswerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AverageAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        MIN(p.Score) AS MinAnswerScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCountOnAnswers,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedAnswersCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
UserQuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.Score) AS TotalQuestionScore,
        AVG(p.Score) AS AverageQuestionScore,
        MAX(p.Score) AS MaxQuestionScore,
        MIN(p.Score) AS MinQuestionScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        COUNT(DISTINCT c.Id) AS CommentCountOnQuestions,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVotesReceived,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVotesReceived,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE NULL END) AS FavoritesAdded,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmountGiven
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotesGiven,
    u.DownVotes AS UserDownVotesGiven,
    u.LastAccessDate,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges WHERE UserId = u.Id AND Name LIKE '%Tag%') THEN 'Has Tag Badge'
        ELSE 'No Tag Badge'
    END AS HasTagBadgeIndicator,
    COALESCE(rq.Title, 'No Recent Question') AS MostRecentQuestionTitle,
    COALESCE(uas.AnswerCount, 0) AS TotalAnswers,
    COALESCE(uq.QuestionCount, 0) AS TotalQuestions,
    COALESCE(uvs.UpVotesReceived, 0) AS TotalUpVotesReceived,
    COALESCE(uvs.DownVotesReceived, 0) AS TotalDownVotesReceived,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadgesCount,
    CASE
        WHEN uas.AverageAnswerScore > 5 THEN 'High Avg Answer Score'
        WHEN uas.AverageAnswerScore < 0 THEN 'Low Avg Answer Score'
        ELSE 'Moderate Avg Answer Score'
    END AS AnswerScoreCategory,
    CASE
        WHEN uq.AverageQuestionScore > 10 THEN 'High Avg Question Score'
        WHEN uq.AverageQuestionScore < 0 THEN 'Low Avg Question Score'
        ELSE 'Moderate Avg Question Score'
    END AS QuestionScoreCategory,
    uq.TotalFavoriteCount AS UserTotalFavoriteCount,
    uqs.CommentCountOnQuestions,
    uas.CommentCountOnAnswers,
    uq.ClosedQuestionsCount,
    uas.ClosedAnswersCount,
    uvs.TotalBountyAmountGiven,
    COALESCE(u.WebsiteUrl, 'No Website Provided') AS UserWebsiteStatus,
    LENGTH(u.AboutMe) AS AboutMeLength,
    CASE
        WHEN u.LastAccessDate < DATE('now', '-1 year') THEN 'Inactive'
        WHEN u.LastAccessDate < DATE('now', '-3 months') THEN 'Moderately Active'
        ELSE 'Active'
    END AS UserActivityStatus,
    CASE
        WHEN u.Reputation BETWEEN 1 AND 99 THEN 'New User'
        WHEN u.Reputation BETWEEN 100 AND 999 THEN 'Novice'
        WHEN u.Reputation BETWEEN 1000 AND 9999 THEN 'Experienced'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        ELSE 'Unranked'
    END AS ReputationTier,
    IIF(u.AccountId IS NULL, 'No Account Link', 'Account Linked') AS AccountLinkStatus,
    CASE
        WHEN u.DisplayName LIKE '% ' THEN 'DisplayNameEndsWithSpace'
        WHEN u.DisplayName LIKE ' %' THEN 'DisplayNameStartsWithSpace'
        ELSE 'DisplayNameStandard'
    END AS DisplayNameFormat,
    CASE
        WHEN u.Location IS NULL OR u.Location = '' THEN 'No Location Specified'
        WHEN u.Location LIKE '%USA%' OR u.Location LIKE '%United States%' THEN 'In USA'
        ELSE 'Outside USA/Unknown'
    END AS LocationRegion,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate BETWEEN u.CreationDate AND DATE('now')) AS PostsSinceCreation,
    CAST(STRFTIME('%Y', u.CreationDate) AS INTEGER) AS UserCreationYear,
    CAST(STRFTIME('%W', u.CreationDate) AS INTEGER) AS UserCreationWeek,
    CASE
        WHEN u.ProfileImageUrl IS NOT NULL AND u.ProfileImageUrl LIKE '%gravatar.com%' THEN 'Uses Gravatar'
        WHEN u.ProfileImageUrl IS NOT NULL THEN 'Uses Custom Avatar'
        ELSE 'No Avatar'
    END AS AvatarType,
    (SELECT SUM(Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) - (SELECT SUM(Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS NetQuestionScore,
    (SELECT COUNT(*) FROM PostLinks pl JOIN Posts p ON pl.PostId = p.Id WHERE p.OwnerUserId = u.Id AND pl.LinkTypeId = 3) AS DuplicateLinksCreated,
    (SELECT COUNT(*) FROM PostLinks pl JOIN Posts p ON pl.RelatedPostId = p.Id WHERE p.OwnerUserId = u.Id AND pl.LinkTypeId = 3) AS DuplicateLinksTargeted,
    COALESCE(u.AboutMe, 'Empty About Me') AS AboutMeStatus,
    ABS(u.Views - u.Reputation) AS ViewReputationDifference,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS GlobalReputationRank
FROM Users u
LEFT JOIN RankedQuestions rq ON u.Id = rq.OwnerUserId AND rq.rn = 1
LEFT JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
LEFT JOIN UserQuestionStats uq ON u.Id = uq.OwnerUserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
WHERE u.Id < 10000 -- Limiting for performance
ORDER BY u.Reputation DESC
LIMIT 100;
