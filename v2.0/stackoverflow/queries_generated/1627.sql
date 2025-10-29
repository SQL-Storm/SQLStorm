-- {"query": "1627.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3409} 

WITH UserEngagement AS (
    -- CTE 1: Summarizes basic user engagement metrics, post counts, and comment counts.
    -- Incorporates filtering by user creation date and uses COALESCE for default counts.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2010-01-01' -- Filter for a specific period for performance
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
PostContentAnalysis AS (
    -- CTE 2: Analyzes post content, extracts tags, and determines post status.
    -- Includes correlated subqueries to fetch initial title and latest body edit history.
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        COALESCE(LENGTH(p.Body), 0) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        REPLACE(TRIM(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)), '><', ',') AS ParsedTags, -- String manipulation for tags
        p.AcceptedAnswerId,
        p.ParentId,
        (SELECT ph_title.Text FROM PostHistory ph_title
         WHERE ph_title.PostId = p.Id AND ph_title.PostHistoryTypeId = 1 -- Initial Title
         ORDER BY ph_title.CreationDate ASC, ph_title.Id ASC LIMIT 1) AS InitialTitle, -- Correlated Subquery 1
        (SELECT ph_edit.Text FROM PostHistory ph_edit
         WHERE ph_edit.PostId = p.Id AND ph_edit.PostHistoryTypeId = 5 -- Edit Body
         ORDER BY ph_edit.CreationDate DESC, ph_edit.Id DESC LIMIT 1) AS LatestBodyEdit, -- Correlated Subquery 2
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL -- Exclude community-owned posts or posts without an owner
),
AggregatedPostMetrics AS (
    -- CTE 3: Aggregates post-related quality metrics per user.
    -- Uses a LATERAL JOIN for tag parsing and another correlated subquery for most recent title edit.
    SELECT
        pca.UserId,
        AVG(CASE WHEN pca.PostTypeId = 1 THEN pca.PostScore ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN pca.PostTypeId = 2 THEN pca.PostScore ELSE NULL END) AS AvgAnswerScore,
        MAX(pca.ViewCount) AS MaxPostViewCount,
        SUM(CASE WHEN pca.PostTypeId = 1 AND pca.PostStatus = 'Answered' THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(pca.BodyLength) AS TotalBodyLength,
        MAX(pca.PostCreationDate) AS LastPostActivityDate,
        MIN(pca.PostCreationDate) AS EarliestPostActivityDate,
        -- Correlated subquery to find the most recent edited title by the user across all their posts
        (SELECT ph.Text
         FROM PostHistory ph
         WHERE ph.UserId = pca.UserId
           AND ph.PostHistoryTypeId = 4 -- Edit Title
         ORDER BY ph.CreationDate DESC, ph.Id DESC
         LIMIT 1
        ) AS UsersMostRecentEditedTitle, -- Correlated Subquery 3
        COUNT(DISTINCT tag_split.value) AS DistinctTagsUsed
    FROM PostContentAnalysis AS pca
    LEFT JOIN LATERAL unnest(string_to_array(pca.ParsedTags, ',')) AS tag_split(value) ON TRUE -- Complex string parsing with LATERAL join
    GROUP BY pca.UserId
),
BadgeSummary AS (
    -- CTE 4: Summarizes badge counts by class for each user.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges AS b
    GROUP BY b.UserId
),
ClosedQuestionStats AS (
    -- CTE 5: Identifies posts that were closed for specific reasons (Duplicate, Off-topic).
    -- Utilizes PostHistory to determine close reasons.
    SELECT
        ph.PostId,
        cr.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes AS cr ON ph.Comment IS NOT NULL AND ph.Comment ~ '^[0-9]+$' AND cr.Id = CAST(ph.Comment AS smallint)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND (cr.Name = 'Duplicate' OR cr.Name LIKE 'Off-topic%')
),
UserPostHistoryDiversity AS (
    -- CTE 6: Measures the diversity of PostHistory types and average text length for user edits.
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctHistoryTypes,
        AVG(LENGTH(ph.Text)) FILTER (WHERE ph.Text IS NOT NULL) AS AvgHistoryTextLength
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
FinalUserProfiles AS (
    -- CTE 7: Combines all previous CTEs and applies various window functions, complex calculations, and NULL logic.
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.UserViews,
        ue.UserUpVotesGiven,
        ue.UserDownVotesGiven,
        ue.QuestionCount,
        ue.AnswerCount,
        ue.TotalPosts,
        ue.TotalPostScore,
        amp.AvgQuestionScore,
        amp.AvgAnswerScore,
        amp.MaxPostViewCount,
        amp.QuestionsWithAcceptedAnswers,
        amp.TotalBodyLength,
        amp.UsersMostRecentEditedTitle,
        amp.DistinctTagsUsed,
        bs.TotalBadges,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.LastBadgeDate,
        uhd.DistinctHistoryTypes,
        uhd.AvgHistoryTextLength,
        -- Window functions for ranking and rolling aggregates
        RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScore DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY ue.TotalPosts DESC) AS PostVolumeDecile,
        SUM(ue.TotalPostScore) OVER (PARTITION BY EXTRACT(YEAR FROM ue.UserCreationDate) ORDER BY ue.UserCreationDate ASC ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS Rolling30DayPostScoreSum,
        LAG(ue.Reputation, 1, 0) OVER (ORDER BY ue.UserCreationDate) AS PreviousUserReputationByCreationOrder,
        -- Complex calculation/expression involving multiple metrics
        (ue.QuestionCount * 0.4 + ue.AnswerCount * 0.6 + ue.TotalComments * 0.1) * (1 + (ue.TotalPostScore / NULLIF(ue.TotalPosts, 0)) / 100.0) AS EngagementScore,
        -- NULL logic with CASE statements for user archetype classification
        CASE
            WHEN ue.QuestionCount = 0 AND ue.AnswerCount = 0 THEN 'No Posts'
            WHEN ue.QuestionCount > ue.AnswerCount AND ue.QuestionCount >= 2 THEN 'Primary Questioner'
            WHEN ue.AnswerCount > ue.QuestionCount AND ue.AnswerCount >= 2 THEN 'Primary Answerer'
            WHEN ue.QuestionCount > 0 AND ue.AnswerCount > 0 THEN 'Balanced Contributor'
            ELSE 'Minor Contributor'
        END AS UserArchetype,
        -- Subquery to count answers provided to questions that were later closed for specific reasons
        (SELECT COUNT(DISTINCT pca.PostId)
         FROM PostContentAnalysis pca
         JOIN ClosedQuestionStats cqs ON pca.ParentId = cqs.PostId -- An answer (pca.PostId) to a closed question (cqs.PostId)
         WHERE pca.UserId = ue.UserId AND pca.PostTypeId = 2
        ) AS AnswersToClosedQuestions,
        -- String expression using COALESCE for a user identifier
        COALESCE(ue.DisplayName, 'Anonymous User') || ' (' || COALESCE(CAST(ue.UserId AS varchar), 'N/A') || ')' AS UserIdentifier,
        -- Correlated subqueries for detailed vote counts
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.UserId = ue.UserId AND v.VoteTypeId = 5) AS FavoritesMadeCount, -- Correlated Subquery 4
        (SELECT COUNT(v.Id) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ue.UserId AND v.VoteTypeId = 2) AS UpVotesReceivedCount, -- Correlated Subquery 5
        (SELECT COUNT(v.Id) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ue.UserId AND v.VoteTypeId = 3) AS DownVotesReceivedCount -- Correlated Subquery 6
    FROM UserEngagement AS ue
    LEFT JOIN AggregatedPostMetrics AS amp ON ue.UserId = amp.UserId
    LEFT JOIN BadgeSummary AS bs ON ue.UserId = bs.UserId
    LEFT JOIN UserPostHistoryDiversity AS uhd ON ue.UserId = uhd.UserId
    WHERE ue.Reputation >= 100 -- Filter for more established users
      AND ue.TotalPosts > 0
),
HighReputationContributors AS (
    -- Categorization of users based on high reputation rank and quality metrics
    SELECT
        fup.UserId,
        'HighReputation' AS ContributionCategory
    FROM FinalUserProfiles AS fup
    WHERE fup.ReputationRank <= 1000
    AND fup.AvgQuestionScore IS NOT NULL
    AND fup.AvgAnswerScore IS NOT NULL
    AND fup.AnswersToClosedQuestions = 0 -- Exclude users answering 'bad' questions
),
HighVolumeContributors AS (
    -- Categorization of users based on high post volume and diverse history activity
    SELECT
        fup.UserId,
        'HighVolume' AS ContributionCategory
    FROM FinalUserProfiles AS fup
    WHERE fup.PostVolumeDecile = 1 -- Top 10% by post volume
    AND fup.DistinctHistoryTypes >= 5 -- Users engaging in diverse history activities
    AND fup.AvgHistoryTextLength > 50 -- Significant history text contributions
)
-- Final SELECT statement, joining all derived data, applying final filters and complex string expressions.
SELECT
    fup.UserId,
    fup.UserIdentifier,
    fup.Reputation,
    fup.UserCreationDate,
    fup.UserArchetype,
    fup.EngagementScore,
    fup.ReputationRank,
    fup.PostVolumeDecile,
    fup.Rolling30DayPostScoreSum,
    fup.PreviousUserReputationByCreationOrder,
    fup.QuestionCount,
    fup.AnswerCount,
    fup.TotalPosts,
    fup.TotalPostScore,
    fup.AvgQuestionScore,
    fup.AvgAnswerScore,
    fup.MaxPostViewCount,
    fup.QuestionsWithAcceptedAnswers,
    fup.TotalBodyLength,
    fup.UsersMostRecentEditedTitle,
    fup.DistinctTagsUsed,
    fup.TotalBadges,
    fup.GoldBadges,
    fup.SilverBadges,
    fup.BronzeBadges,
    fup.LastBadgeDate,
    fup.DistinctHistoryTypes,
    fup.AvgHistoryTextLength,
    fup.AnswersToClosedQuestions,
    fup.FavoritesMadeCount,
    fup.UpVotesReceivedCount,
    fup.DownVotesReceivedCount,
    COALESCE(hrc.ContributionCategory, hvc.ContributionCategory, 'General') AS UserContributionClassification, -- Outer join logic for classification
    -- Elaborate string expression combining multiple user attributes
    UPPER(LEFT(COALESCE(fup.DisplayName, 'UNKNOWN'), 3)) || '-' || LPAD(CAST(fup.QuestionCount + fup.AnswerCount AS TEXT), 5, '0') || '-' || RIGHT(CAST(fup.TotalPostScore + ABS(fup.TotalPostScore) AS TEXT), 5) AS UniqueUserSignature
FROM FinalUserProfiles AS fup
LEFT JOIN HighReputationContributors AS hrc ON fup.UserId = hrc.UserId
LEFT JOIN HighVolumeContributors AS hvc ON fup.UserId = hvc.UserId
WHERE fup.EngagementScore > 50 -- Apply a final filter on the calculated score
  AND fup.TotalPosts >= 5 -- Ensure a minimum level of activity
ORDER BY fup.ReputationRank ASC, fup.EngagementScore DESC, fup.UserId ASC
LIMIT 1000;
