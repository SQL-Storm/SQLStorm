-- {"query": "1026.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4201} 

WITH UserActivityMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserRegistrationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        u.Location,
        u.AboutMe,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.OwnerUserId = u.Id) AS TotalPostsOwned,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS TotalQuestionsOwned,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS TotalAnswersOwned,
        COALESCE(SUM(p.Score) FILTER (WHERE p.OwnerUserId = u.Id), 0) AS TotalPostsScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.OwnerUserId = u.Id), 0.0) AS AvgPostScoreOwned,
        MAX(p.LastActivityDate) FILTER (WHERE p.OwnerUserId = u.Id) AS LastOwnedPostActivity,
        COUNT(DISTINCT c.Id) FILTER (WHERE c.UserId = u.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(b.Date) AS LastBadgeDate,
        MIN(p.CreationDate) FILTER (WHERE p.OwnerUserId = u.Id) AS FirstPostDateOwned,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS DaysSinceAccountCreation,
        NULLIF(u.Reputation, 0) / NULLIF(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24), 0) AS AvgReputationPerDayActive -- Handles division by zero for very new users
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe
),
QuestionMetaInfo AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.LastActivityDate AS QuestionLastActivityDate,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore,
        a.OwnerUserId AS AcceptedAnswerOwnerUserId,
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><') AS ParsedTags,
        EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10) AS WasClosedEver,
        EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 11) AS WasReopenedEver,
        (SELECT COUNT(DISTINCT pl_dup.RelatedPostId) FROM PostLinks pl_dup WHERE pl_dup.PostId = q.Id AND pl_dup.LinkTypeId = 3) AS DuplicateLinkCount,
        (SELECT MAX(ph_edit.CreationDate) FROM PostHistory ph_edit WHERE ph_edit.PostId = q.Id AND ph_edit.PostHistoryTypeId IN (4,5,6)) AS LastEditDateByAnyone,
        (SELECT COUNT(*) FROM Comments qc WHERE qc.PostId = q.Id) AS QuestionCommentCount
    FROM Posts q
    WHERE q.PostTypeId = 1
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
),
UserQuestionTagPerformance AS (
    SELECT
        qmi.OwnerUserId AS UserId,
        tag_name.unnested_tag AS TagName,
        COUNT(qmi.QuestionId) AS QuestionsInTag,
        SUM(qmi.QuestionScore) AS TotalTagScore,
        COALESCE(AVG(qmi.QuestionScore), 0.0) AS AvgTagQuestionScore,
        MAX(qmi.QuestionCreationDate) AS LatestQuestionInTagDate,
        RANK() OVER (PARTITION BY tag_name.unnested_tag ORDER BY SUM(qmi.QuestionScore) DESC, COUNT(qmi.QuestionId) DESC) AS RankInTagByScore
    FROM QuestionMetaInfo qmi
    LEFT JOIN LATERAL UNNEST(qmi.ParsedTags) AS tag_name(unnested_tag) ON TRUE
    WHERE tag_name.unnested_tag IS NOT NULL
    GROUP BY qmi.OwnerUserId, tag_name.unnested_tag
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalActualEdits,
        MIN(ph.CreationDate) AS FirstEditAttemptDate,
        MAX(ph.CreationDate) AS LastEditAttemptDate,
        AVG(
            CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN
                EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / (60 * 60 * 24) -- Days between edits
            ELSE NULL END
        ) AS AvgDaysBetweenEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 16 THEN 'True' ELSE 'False' END) AS WasCommunityWiki
    FROM PostHistory ph
    GROUP BY ph.PostId
),
RankedUserPosts AS (
    SELECT
        qmi.OwnerUserId AS UserId,
        qmi.QuestionId,
        qmi.QuestionTitle,
        qmi.QuestionScore,
        qmi.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY qmi.OwnerUserId ORDER BY qmi.QuestionScore DESC, qmi.ViewCount DESC, qmi.QuestionCreationDate DESC) AS rn_best_q_score_view,
        ROW_NUMBER() OVER (PARTITION BY qmi.OwnerUserId ORDER BY qmi.QuestionCreationDate DESC) AS rn_latest_q
    FROM QuestionMetaInfo qmi
),
UsersWithPrimaryTag AS (
    SELECT
        sq.UserId,
        sq.TagName AS PrimaryTagName,
        sq.QuestionsInTag,
        sq.TotalTagScore,
        sq.AvgTagQuestionScore,
        sq.RankInTagByScore,
        ROW_NUMBER() OVER (PARTITION BY sq.UserId ORDER BY sq.TotalTagScore DESC, sq.QuestionsInTag DESC) AS rn_primary_tag
    FROM UserQuestionTagPerformance sq
)
-- Main query starts here, combining two groups of users with UNION ALL
SELECT
    -- User Core Information
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.UserRegistrationDate,
    uam.LastAccessDate,
    uam.Location,
    uam.UserProfileViews,

    -- User Activity Aggregates
    uam.TotalPostsOwned,
    uam.TotalQuestionsOwned,
    uam.TotalAnswersOwned,
    uam.TotalCommentsMade,
    uam.TotalBadgesEarned,
    uam.LastBadgeDate,
    
    -- Derived User Metrics
    COALESCE(uam.AvgReputationPerDayActive, 0.0) AS ReputationPerDayActive,
    CASE
        WHEN uam.TotalQuestionsOwned > 0 AND uam.TotalAnswersOwned > 0 THEN 'Contributor & Answerer'
        WHEN uam.TotalQuestionsOwned > 0 THEN 'Questioner'
        WHEN uam.TotalAnswersOwned > 0 THEN 'Answerer'
        ELSE 'Commenter Only'
    END AS UserRoleCategory,
    'https://stackoverflow.com/users/' || uam.UserId AS UserProfileLink,
    
    -- Best Question Details for each user (based on score and view count)
    best_q.QuestionId AS BestQuestionId,
    best_q.QuestionTitle AS BestQuestionTitle,
    best_q.QuestionScore AS BestQuestionScore,
    best_q.ViewCount AS BestQuestionViewCount,
    qmi_best.AcceptedAnswerScore AS BestQuestionAcceptedAnswerScore,
    qmi_best.AcceptedAnswerOwnerUserId AS BestQuestionAcceptedAnswerOwner,
    qmi_best.WasClosedEver AS BestQuestionWasClosed,
    qmi_best.DuplicateLinkCount AS BestQuestionDuplicateLinks,
    qmi_best.QuestionCommentCount AS BestQuestionCommentCount,
    ARRAY_LENGTH(qmi_best.ParsedTags, 1) AS BestQuestionTagCount,
    
    -- Latest Question Details for each user
    latest_q.QuestionId AS LatestQuestionId,
    latest_q.QuestionTitle AS LatestQuestionTitle,
    latest_q.QuestionCreationDate AS LatestQuestionCreationDate,
    
    -- Primary Tag Contribution for each user
    upt.PrimaryTagName,
    upt.QuestionsInTag AS UserQuestionsInPrimaryTag,
    upt.TotalTagScore AS UserTotalScoreInPrimaryTag,
    upt.AvgTagQuestionScore AS UserAvgScoreInPrimaryTag,
    upt.RankInTagByScore AS UserRankInPrimaryTag,
    
    -- Post History Complexity for the Best Question
    phd_best_q.TotalActualEdits AS BestQuestionTotalEdits,
    phd_best_q.AvgDaysBetweenEdits AS BestQuestionAvgDaysBetweenEdits,
    phd_best_q.WasCommunityWiki AS BestQuestionCommunityWikiStatus,
    
    -- Global and Segmented Rankings
    RANK() OVER (ORDER BY uam.Reputation DESC, uam.TotalPostsOwned DESC) AS GlobalReputationRank,
    NTILE(10) OVER (ORDER BY uam.Reputation DESC) AS ReputationDecile, -- Divide users into 10 reputation groups
    
    -- Complex Predicate / Conditional Expression for User Engagement Tier
    CASE
        WHEN uam.Reputation > 10000 AND uam.TotalQuestionsOwned >= 50 AND uam.TotalAnswersOwned >= 100 THEN 'Elite Power User'
        WHEN uam.Reputation > 1000 AND uam.TotalPostsOwned >= 50 THEN 'Active Contributor'
        WHEN uam.TotalPostsOwned > 0 OR uam.TotalCommentsMade > 0 THEN 'Engaged Participant'
        ELSE 'Passive User'
    END AS UserEngagementTier,
    
    -- String manipulations
    LOWER(uam.DisplayName) AS LowerCaseDisplayName,
    SUBSTRING(uam.Location, 1, 30) AS TruncatedLocation,
    COALESCE(NULLIF(REPLACE(uam.AboutMe, CHR(10), ' '), ''), '[No About Me]') AS CleanedAboutMeSnippet, -- Replaces newlines and handles empty string after replace
    TRIM(SPLIT_PART(best_q.QuestionTitle, ' ', 1)) AS FirstWordOfBestQuestionTitle,
    
    -- NULL Logic & Correlated Subquery
    COALESCE(uam.FirstPostDateOwned, uam.UserRegistrationDate) AS EffectiveStartDate,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = best_q.QuestionId AND v.VoteTypeId = 2) AS BestQuestionUpVoteCount, -- Correlated Subquery: Upvotes for the user's best question
    
    'High-Reputation Users' AS SourceGroup
FROM UserActivityMetrics uam
LEFT JOIN RankedUserPosts best_q ON uam.UserId = best_q.UserId AND best_q.rn_best_q_score_view = 1
LEFT JOIN QuestionMetaInfo qmi_best ON best_q.QuestionId = qmi_best.QuestionId
LEFT JOIN RankedUserPosts latest_q ON uam.UserId = latest_q.UserId AND latest_q.rn_latest_q = 1
LEFT JOIN UsersWithPrimaryTag upt ON uam.UserId = upt.UserId AND upt.rn_primary_tag = 1
LEFT JOIN PostHistoryDetails phd_best_q ON best_q.QuestionId = phd_best_q.PostId
WHERE uam.Reputation > 5000 AND uam.TotalPostsOwned > 10

UNION ALL

SELECT
    -- User Core Information
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.UserRegistrationDate,
    uam.LastAccessDate,
    uam.Location,
    uam.UserProfileViews,

    -- User Activity Aggregates
    uam.TotalPostsOwned,
    uam.TotalQuestionsOwned,
    uam.TotalAnswersOwned,
    uam.TotalCommentsMade,
    uam.TotalBadgesEarned,
    uam.LastBadgeDate,
    
    -- Derived User Metrics
    COALESCE(uam.AvgReputationPerDayActive, 0.0) AS ReputationPerDayActive,
    CASE
        WHEN uam.TotalQuestionsOwned > 0 AND uam.TotalAnswersOwned > 0 THEN 'Contributor & Answerer'
        WHEN uam.TotalQuestionsOwned > 0 THEN 'Questioner'
        WHEN uam.TotalAnswersOwned > 0 THEN 'Answerer'
        ELSE 'Commenter Only'
    END AS UserRoleCategory,
    'https://stackoverflow.com/users/' || uam.UserId AS UserProfileLink,
    
    -- Best Question Details for each user
    best_q.QuestionId AS BestQuestionId,
    best_q.QuestionTitle AS BestQuestionTitle,
    best_q.QuestionScore AS BestQuestionScore,
    best_q.ViewCount AS BestQuestionViewCount,
    qmi_best.AcceptedAnswerScore AS BestQuestionAcceptedAnswerScore,
    qmi_best.AcceptedAnswerOwnerUserId AS BestQuestionAcceptedAnswerOwner,
    qmi_best.WasClosedEver AS BestQuestionWasClosed,
    qmi_best.DuplicateLinkCount AS BestQuestionDuplicateLinks,
    qmi_best.QuestionCommentCount AS BestQuestionCommentCount,
    ARRAY_LENGTH(qmi_best.ParsedTags, 1) AS BestQuestionTagCount,
    
    -- Latest Question Details for each user
    latest_q.QuestionId AS LatestQuestionId,
    latest_q.QuestionTitle AS LatestQuestionTitle,
    latest_q.QuestionCreationDate AS LatestQuestionCreationDate,
    
    -- Primary Tag Contribution
    upt.PrimaryTagName,
    upt.QuestionsInTag AS UserQuestionsInPrimaryTag,
    upt.TotalTagScore AS UserTotalScoreInPrimaryTag,
    upt.AvgTagQuestionScore AS UserAvgScoreInPrimaryTag,
    upt.RankInTagByScore AS UserRankInPrimaryTag,
    
    -- Post History Complexity for the Best Question
    phd_best_q.TotalActualEdits AS BestQuestionTotalEdits,
    phd_best_q.AvgDaysBetweenEdits AS BestQuestionAvgDaysBetweenEdits,
    phd_best_q.WasCommunityWiki AS BestQuestionCommunityWikiStatus,
    
    -- Global and Segmented Rankings
    RANK() OVER (ORDER BY uam.Reputation DESC, uam.TotalPostsOwned DESC) AS GlobalReputationRank,
    NTILE(10) OVER (ORDER BY uam.Reputation DESC) AS ReputationDecile,
    
    -- Complex Predicate / Conditional Expression
    CASE
        WHEN uam.Reputation > 10000 AND uam.TotalQuestionsOwned >= 50 AND uam.TotalAnswersOwned >= 100 THEN 'Elite Power User'
        WHEN uam.Reputation > 1000 AND uam.TotalPostsOwned >= 50 THEN 'Active Contributor'
        WHEN uam.TotalPostsOwned > 0 OR uam.TotalCommentsMade > 0 THEN 'Engaged Participant'
        ELSE 'Passive User'
    END AS UserEngagementTier,
    
    -- String manipulations
    LOWER(uam.DisplayName) AS LowerCaseDisplayName,
    SUBSTRING(uam.Location, 1, 30) AS TruncatedLocation,
    COALESCE(NULLIF(REPLACE(uam.AboutMe, CHR(10), ' '), ''), '[No About Me]') AS CleanedAboutMeSnippet,
    TRIM(SPLIT_PART(best_q.QuestionTitle, ' ', 1)) AS FirstWordOfBestQuestionTitle,
    
    -- NULL Logic & Correlated Subquery
    COALESCE(uam.FirstPostDateOwned, uam.UserRegistrationDate) AS EffectiveStartDate,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = best_q.QuestionId AND v.VoteTypeId = 2) AS BestQuestionUpVoteCount,
    
    'Medium-Reputation & Recent Activity Users' AS SourceGroup
FROM UserActivityMetrics uam
LEFT JOIN RankedUserPosts best_q ON uam.UserId = best_q.UserId AND best_q.rn_best_q_score_view = 1
LEFT JOIN QuestionMetaInfo qmi_best ON best_q.QuestionId = qmi_best.QuestionId
LEFT JOIN RankedUserPosts latest_q ON uam.UserId = latest_q.UserId AND latest_q.rn_latest_q = 1
LEFT JOIN UsersWithPrimaryTag upt ON uam.UserId = upt.UserId AND upt.rn_primary_tag = 1
LEFT JOIN PostHistoryDetails phd_best_q ON best_q.QuestionId = phd_best_q.PostId
WHERE uam.Reputation BETWEEN 100 AND 5000
  AND uam.TotalPostsOwned > 5
  AND uam.LastAccessDate > NOW() - INTERVAL '6 months';
