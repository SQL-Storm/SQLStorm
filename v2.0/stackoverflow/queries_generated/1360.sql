-- {"query": "1360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3206} 
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersGiven,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(COALESCE(p.Score, 0)) AS AveragePostScore,
        AVG(COALESCE(c.Score, 0)) AS AverageCommentScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
QuestionActivity AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Title AS QuestionTitle,
        q.Tags AS QuestionTags,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.AnswerCount AS QuestionAnswerCount,
        q.FavoriteCount AS QuestionFavoriteCount,
        q.LastActivityDate AS QuestionLastActivityDate,
        q.ClosedDate,
        q.AcceptedAnswerId,
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDate, -- Last body/title/tags edit
        COUNT(ph_all.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph_all.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN ph_all.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN ph_all.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        SUM(CASE WHEN ph_all.PostHistoryTypeId IN (35,36) THEN 1 ELSE 0 END) AS MigrationEvents,
        MAX(CASE WHEN ph_all.PostHistoryTypeId = 10 THEN ph_all.CreationDate ELSE NULL END) AS LatestCloseEventDate
    FROM Posts q
    LEFT JOIN PostHistory ph_all ON q.Id = ph_all.PostId
    WHERE q.PostTypeId = 1 -- Only questions
    GROUP BY
        q.Id, q.OwnerUserId, q.CreationDate, q.Title, q.Tags, q.Score, q.ViewCount,
        q.AnswerCount, q.FavoriteCount, q.LastActivityDate, q.ClosedDate, q.AcceptedAnswerId
),
AnswerAggregates AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS ActualAnswerCount,
        SUM(a.Score) AS TotalAnswersScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Score ELSE 0 END) AS AcceptedAnswerScore
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id AND a.PostTypeId = 2 AND q.PostTypeId = 1
    GROUP BY a.ParentId, q.AcceptedAnswerId
),
CommentSentiment AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%thank%' OR LOWER(c.Text) LIKE '%great%' OR LOWER(c.Text) LIKE '%appreciate%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%wrong%' OR LOWER(c.Text) LIKE '%bug%' OR LOWER(c.Text) LIKE '%error%' THEN 1 ELSE 0 END) AS NegativeCommentCount
    FROM Comments c
    GROUP BY c.PostId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS TotalLinkedPosts,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS TotalDuplicateLinks, -- PostId is a duplicate of RelatedPostId
        MAX(CASE WHEN pl.LinkTypeId = 3 THEN pl.CreationDate ELSE NULL END) AS LatestDuplicateLinkDate
    FROM PostLinks pl
    GROUP BY pl.PostId
),
RankedActivity AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalQuestionsAsked,
        ue.TotalAnswersGiven,
        ue.GoldBadges,
        qa.QuestionId,
        qa.QuestionTitle,
        qa.QuestionScore,
        qa.QuestionViewCount,
        qa.QuestionAnswerCount,
        qa.TotalEdits,
        qa.CloseEvents,
        aa.ActualAnswerCount,
        aa.TotalAnswersScore,
        aa.AvgAnswerScore,
        cs.TotalComments,
        cs.PositiveCommentCount,
        cs.NegativeCommentCount,
        pla.TotalLinkedPosts,
        pla.TotalDuplicateLinks,
        -- Window function to rank users by reputation among those who asked questions
        RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalQuestionsAsked DESC) AS UserReputationRank,
        -- Window function to calculate rolling average score of questions for each user
        AVG(qa.QuestionScore) OVER (PARTITION BY ue.UserId ORDER BY qa.QuestionCreationDate) AS UserRollingAvgQuestionScore,
        -- LEAD/LAG to see activity before/after a question was closed
        LAG(qa.QuestionScore, 1, 0) OVER (PARTITION BY ue.UserId ORDER BY qa.QuestionCreationDate) AS PrevQuestionScore,
        LEAD(qa.QuestionScore, 1, 0) OVER (PARTITION BY ue.UserId ORDER BY qa.QuestionCreationDate) AS NextQuestionScore,
        -- Identify users with highly volatile question scores
        (qa.QuestionScore - LAG(qa.QuestionScore, 1, qa.QuestionScore) OVER (PARTITION BY ue.UserId ORDER BY qa.QuestionCreationDate)) AS ScoreDelta,
        -- Check if user's last access date is after their last edit on a post
        CASE
            WHEN ue.LastAccessDate > qa.LastEditDate THEN 'AccessedAfterLastEdit'
            ELSE 'AccessedBeforeLastEdit'
        END AS AccessEditTimingFlag,
        -- Correlated subquery: Check if the user has any 'Great Answer' badge (Class = 2, Name = 'Great Answer') before the question was created
        EXISTS (
            SELECT 1
            FROM Badges b_corr
            WHERE b_corr.UserId = ue.UserId
              AND b_corr.Class = 2
              AND b_corr.Name = 'Great Answer'
              AND b_corr.Date < qa.QuestionCreationDate
        ) AS HasGreatAnswerBadgeBeforeQuestion
    FROM UserEngagement ue
    INNER JOIN QuestionActivity qa ON ue.UserId = qa.QuestionOwnerUserId
    LEFT JOIN AnswerAggregates aa ON qa.QuestionId = aa.QuestionId
    LEFT JOIN CommentSentiment cs ON qa.QuestionId = cs.PostId
    LEFT JOIN PostLinkAnalysis pla ON qa.QuestionId = pla.PostId
    WHERE ue.Reputation > 5000 -- Filter for more active/influential users
      AND qa.QuestionCreationDate >= '2020-01-01'
      AND qa.QuestionCreationDate < '2023-01-01'
      AND (qa.QuestionViewCount > 1000 OR qa.QuestionFavoriteCount > 50)
),
FrequentTagUsers AS (
    SELECT
        q.OwnerUserId AS UserId,
        LOWER(TRIM(t.tag_value)) AS TagName,
        COUNT(*) AS TagUsageCount
    FROM Posts q
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t(tag_value)
    WHERE q.PostTypeId = 1
      AND q.Tags IS NOT NULL
      AND q.Tags != ''
    GROUP BY q.OwnerUserId, LOWER(TRIM(t.tag_value))
    HAVING COUNT(*) > 10 -- Users who frequently use certain tags
),
TopQuestionTags AS (
    SELECT
        ftu.UserId,
        ftu.TagName,
        ftu.TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY ftu.UserId ORDER BY ftu.TagUsageCount DESC) AS TagRankForUser
    FROM FrequentTagUsers ftu
),
CombinedUserQuestionData AS (
    SELECT
        ra.UserId,
        ra.DisplayName,
        ra.Reputation,
        ra.TotalQuestionsAsked,
        ra.TotalAnswersGiven,
        ra.GoldBadges,
        ra.QuestionId,
        ra.QuestionTitle,
        ra.QuestionScore,
        ra.QuestionViewCount,
        ra.QuestionAnswerCount,
        ra.TotalEdits,
        ra.CloseEvents,
        ra.ActualAnswerCount,
        ra.TotalAnswersScore,
        ra.AvgAnswerScore,
        ra.TotalComments,
        ra.PositiveCommentCount,
        ra.NegativeCommentCount,
        ra.TotalLinkedPosts,
        ra.TotalDuplicateLinks,
        ra.UserReputationRank,
        ra.UserRollingAvgQuestionScore,
        ra.PrevQuestionScore,
        ra.NextQuestionScore,
        ra.ScoreDelta,
        ra.AccessEditTimingFlag,
        ra.HasGreatAnswerBadgeBeforeQuestion,
        tqt.TagName AS TopFrequentTag,
        tqt.TagUsageCount AS TopFrequentTagCount
    FROM RankedActivity ra
    LEFT JOIN TopQuestionTags tqt ON ra.UserId = tqt.UserId AND tqt.TagRankForUser = 1
),
HighlyVolatileUsers AS (
    SELECT
        cud.UserId,
        cud.DisplayName,
        MAX(cud.Reputation) AS Reputation,
        COUNT(DISTINCT cud.QuestionId) AS QuestionsAnalyzed,
        AVG(ABS(cud.ScoreDelta)) AS AvgAbsoluteScoreDelta,
        SUM(CASE WHEN cud.ScoreDelta < -100 THEN 1 ELSE 0 END) AS SignificantScoreDrops, -- Questions with large score drops
        MAX(CASE WHEN cud.HasGreatAnswerBadgeBeforeQuestion THEN 1 ELSE 0 END) AS HadGreatAnswerBadge,
        AVG(COALESCE(cud.TotalEdits, 0)) AS AvgEditsPerQuestion,
        AVG(COALESCE(cud.CloseEvents, 0)) AS AvgCloseEventsPerQuestion
    FROM CombinedUserQuestionData cud
    GROUP BY cud.UserId, cud.DisplayName
    HAVING COUNT(DISTINCT cud.QuestionId) > 2 -- Analyze users with more than 2 questions in the period
       AND AVG(ABS(cud.ScoreDelta)) > 50 -- Filter for users whose question scores are highly volatile
)
SELECT
    hvu.DisplayName AS UserDisplayName,
    hvu.Reputation,
    hvu.QuestionsAnalyzed,
    hvu.AvgAbsoluteScoreDelta,
    hvu.SignificantScoreDrops,
    CASE WHEN hvu.HadGreatAnswerBadge = 1 THEN 'Yes' ELSE 'No' END AS HadGreatAnswerBadge,
    hvu.AvgEditsPerQuestion,
    hvu.AvgCloseEventsPerQuestion,
    MAX(CASE WHEN cud.AccessEditTimingFlag = 'AccessedAfterLastEdit' THEN 1 ELSE 0 END) AS HasAccessedAfterEdit,
    MAX(cud.TopFrequentTag) AS MostFrequentTag,
    MAX(cud.TopFrequentTagCount) AS MostFrequentTagCount,
    -- Calculate overall average question score for comparison
    (SELECT AVG(q_total.Score) FROM Posts q_total WHERE q_total.PostTypeId = 1 AND q_total.CreationDate >= '2020-01-01' AND q_total.CreationDate < '2023-01-01') AS OverallAvgQuestionScore,
    -- Calculate average gold badges for all users who asked questions in the period
    (SELECT AVG(ug.GoldBadges) FROM UserEngagement ug WHERE ug.TotalQuestionsAsked > 0) AS OverallAvgGoldBadgesForQuestionAskerrs
FROM HighlyVolatileUsers hvu
INNER JOIN CombinedUserQuestionData cud ON hvu.UserId = cud.UserId
GROUP BY
    hvu.DisplayName,
    hvu.Reputation,
    hvu.QuestionsAnalyzed,
    hvu.AvgAbsoluteScoreDelta,
    hvu.SignificantScoreDrops,
    hvu.HadGreatAnswerBadge,
    hvu.AvgEditsPerQuestion,
    hvu.AvgCloseEventsPerQuestion
HAVING hvu.SignificantScoreDrops > 0 OR hvu.AvgEditsPerQuestion > 2
ORDER BY hvu.Reputation DESC, hvu.AvgAbsoluteScoreDelta DESC, hvu.SignificantScoreDrops DESC
LIMIT 100;