-- {"query": "19085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3278} 

WITH UserEngagementSummary AS (
    -- Aggregates various engagement metrics for each user, including post/comment scores and badge counts
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsCreated,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersCreated,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)), 0) AS TotalPostScoreReceived,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0.0) AS AvgQuestionScoreReceived,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0.0) AS AvgAnswerScoreReceived,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsMade,
        COALESCE(AVG(c.Score) FILTER (WHERE c.UserId = u.Id), 0.0) AS AvgCommentScoreMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(v.CreationDate) AS LastVoteCastDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / (60 * 60 * 24 * 365.25) AS AccountAgeYears
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
QuestionDetailedMetrics AS (
    -- Focuses on questions, adding details like answer counts, editor counts, and closure reasons
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.ViewCount AS QuestionViewCount,
        q.Score AS QuestionScore,
        q.OwnerUserId,
        q.Tags AS QuestionTagsRaw,
        q.AcceptedAnswerId,
        COALESCE(q.AnswerCount, 0) AS DeclaredAnswerCount,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS ActualAnswerCount,
        COALESCE(AVG(a.Score) FILTER (WHERE a.PostTypeId = 2), 0.0) AS AverageAnswerScore,
        MAX(a.CreationDate) FILTER (WHERE a.PostTypeId = 2) AS LastAnswerCreationDate,
        SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount,
        (SELECT COUNT(DISTINCT pl_dup.RelatedPostId) FROM PostLinks pl_dup WHERE pl_dup.PostId = q.Id AND pl_dup.LinkTypeId = 3) AS DuplicatePostsCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND crt.Name IS NOT NULL THEN crt.Name ELSE NULL END) AS LastClosureReason,
        COUNT(DISTINCT ph_edit.UserId) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorsBesidesOwner,
        MAX(ph_activity.CreationDate) AS LastPostHistoryActivityDate,
        LAG(q.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS PreviousQuestionCreationDate
    FROM
        Posts q
    LEFT JOIN
        Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN
        PostHistory ph ON q.Id = ph.PostId AND ph.PostHistoryTypeId = 10 -- For closure info
    LEFT JOIN
        CloseReasonTypes crt ON CAST(ph.Comment AS smallint) = crt.Id -- Linking close reason
    LEFT JOIN
        PostHistory ph_edit ON q.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4,5,6) -- For unique editors
    LEFT JOIN
        PostHistory ph_activity ON q.Id = ph_activity.PostId -- For last activity date
    WHERE
        q.PostTypeId = 1 -- Only questions
    GROUP BY
        q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.OwnerUserId, q.Tags, q.AnswerCount, q.AcceptedAnswerId
),
TagPerformanceMetrics AS (
    -- Calculates average performance for each tag based on associated questions
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName,
        COUNT(DISTINCT p.Id) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgTagQuestionScore,
        AVG(p.ViewCount) AS AvgTagQuestionViewCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributorsToTag,
        MIN(p.CreationDate) AS TagFirstSeenDate
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')))
    HAVING
        COUNT(DISTINCT p.Id) > 50 -- Filter out less common tags
),
CombinedUserQuestionTagData AS (
    -- Joins user engagement, question details, and extracts the primary tag
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.TotalPostsCreated,
        ues.TotalQuestionsCreated,
        ues.AvgQuestionScoreReceived,
        ues.AvgAnswerScoreReceived,
        ues.GoldBadges,
        ues.SilverBadges,
        q_det.QuestionId,
        q_det.QuestionTitle,
        q_det.QuestionScore,
        q_det.QuestionCreationDate,
        q_det.QuestionViewCount,
        q_det.ActualAnswerCount,
        q_det.AverageAnswerScore,
        q_det.LastClosureReason,
        q_det.UniqueEditorsBesidesOwner,
        TRIM(SPLIT_PART(SUBSTRING(q_det.QuestionTagsRaw FROM 2 FOR LENGTH(q_det.QuestionTagsRaw)-2), '><', 1)) AS PrimaryTag,
        ues.AccountAgeYears,
        EXTRACT(EPOCH FROM (q_det.QuestionCreationDate - q_det.PreviousQuestionCreationDate)) / (60 * 60 * 24) AS DaysSinceLastQuestion
    FROM
        UserEngagementSummary ues
    INNER JOIN
        QuestionDetailedMetrics q_det ON ues.UserId = q_det.OwnerUserId
    WHERE
        ues.TotalPostsCreated > 10
        AND q_det.QuestionViewCount > 1000
        AND q_det.ActualAnswerCount >= 1
)
-- Final selection, ranking, and complex categorization
SELECT
    cuq.UserId,
    cuq.DisplayName,
    cuq.Reputation,
    cuq.PrimaryTag,
    cuq.QuestionId,
    cuq.QuestionTitle,
    cuq.QuestionScore,
    cuq.QuestionViewCount,
    cuq.ActualAnswerCount,
    tpm.AvgTagQuestionScore,
    tpm.AvgTagQuestionViewCount,
    cuq.GoldBadges,
    cuq.SilverBadges,
    -- Window functions for ranking and aggregation
    RANK() OVER (PARTITION BY cuq.PrimaryTag ORDER BY cuq.QuestionScore DESC, cuq.QuestionViewCount DESC) AS RankInTagByQuestionPerformance,
    NTILE(5) OVER (ORDER BY cuq.Reputation DESC, cuq.AvgQuestionScoreReceived DESC) AS UserOverallPerformanceQuintile,
    SUM(cuq.ActualAnswerCount) OVER (PARTITION BY cuq.UserId) AS TotalAnswersOnUsersQuestions,
    COALESCE(
        MAX(CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN 'Reopened' ELSE NULL END) OVER (PARTITION BY cuq.QuestionId),
        'Not Reopened'
    ) AS QuestionReopenStatus,
    -- Correlated subquery to find the highest score of an answer provided by this specific author for this specific question
    (
        SELECT COALESCE(MAX(ans.Score), 0)
        FROM Posts ans
        WHERE ans.ParentId = cuq.QuestionId
          AND ans.PostTypeId = 2
          AND ans.OwnerUserId = cuq.UserId
    ) AS HighestAuthorSelfAnswerScore,
    -- Correlated subquery to check if any comment from the owner contains specific keywords
    (
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = cuq.QuestionId AND c.UserId = cuq.UserId AND (c.Text ILIKE '%duplicate%' OR c.Text ILIKE '%clarify%'))
                THEN 'Discusses Duplicates/Clarity'
                ELSE 'No Specific Discussion'
            END
    ) AS OwnerCommentAnalysis,
    -- Complex CASE expression for user categorization based on multiple criteria
    CASE
        WHEN cuq.Reputation > 75000 AND cuq.GoldBadges >= 5 AND cuq.AvgQuestionScoreReceived > 20 AND cuq.AccountAgeYears > 5 THEN 'Legendary Architect'
        WHEN cuq.Reputation > 25000 AND cuq.SilverBadges >= 10 AND tpm.AvgTagQuestionScore > 15 AND cuq.DaysSinceLastQuestion IS NOT NULL AND cuq.DaysSinceLastQuestion <= 90 THEN 'Elite Domain Expert (Active)'
        WHEN cuq.ReputationQuartile = 1 AND cuq.AvgQuestionScoreReceived > tpm.AvgTagQuestionScore * 1.5 AND cuq.QuestionViewCount > tpm.AvgTagQuestionViewCount THEN 'High-Impact Rising Star'
        WHEN cuq.LastClosureReason IS NOT NULL AND cuq.LastClosureReason = 'Duplicate' AND QuestionReopenStatus = 'Reopened' THEN 'Resolved Duplicate Question Author'
        WHEN cuq.AvgAnswerScoreReceived > cuq.AvgQuestionScoreReceived * 2 THEN 'Strong Answerer, Moderate Questioner'
        ELSE 'Active Contributor'
    END AS DetailedUserCategory,
    -- String manipulations
    UPPER(LEFT(COALESCE(cuq.DisplayName, 'Unknown'), 3)) AS DisplayNamePrefix,
    LENGTH(cuq.QuestionTitle) AS QuestionTitleLength,
    REPLACE(REPLACE(cuq.QuestionTitle, 'how to', 'How-To'), 'What is', 'What-Is') AS TitleProcessedForKeywords,
    NULLIF(cuq.LastClosureReason, 'Not a real question') AS FilteredClosureReason -- Demonstrate NULLIF
FROM
    CombinedUserQuestionTagData cuq
INNER JOIN
    TagPerformanceMetrics tpm ON cuq.PrimaryTag = tpm.TagName
LEFT JOIN
    PostHistory ph_reopen ON cuq.QuestionId = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11 -- For reopen status
WHERE
    cuq.Reputation > 5000 -- Focus on more established users
    AND cuq.PrimaryTag LIKE '%.js%' -- Filter for JavaScript-related tags (e.g., node.js, react.js, vue.js)
    AND cuq.QuestionScore > tpm.AvgTagQuestionScore * 0.8 -- Question score is at least 80% of tag average
    AND cuq.DaysSinceLastQuestion IS NOT NULL AND cuq.DaysSinceLastQuestion BETWEEN 7 AND 365 -- Recent and regular question activity
    AND cuq.AccountAgeYears >= 1 -- Account is at least a year old
GROUP BY -- Grouping to allow for HAVING clause usage and ensure distinctness based on selection
    cuq.UserId, cuq.DisplayName, cuq.Reputation, cuq.PrimaryTag, cuq.QuestionId, cuq.QuestionTitle,
    cuq.QuestionScore, cuq.QuestionViewCount, cuq.ActualAnswerCount, tpm.AvgTagQuestionScore,
    tpm.AvgTagQuestionViewCount, cuq.GoldBadges, cuq.SilverBadges, cuq.AvgQuestionScoreReceived,
    cuq.AvgAnswerScoreReceived, cuq.LastClosureReason, cuq.DaysSinceLastQuestion, cuq.AccountAgeYears,
    cuq.UniqueEditorsBesidesOwner, ph_reopen.PostHistoryTypeId -- Include ph_reopen.PostHistoryTypeId for distinctness in MAX OVER()
HAVING
    COUNT(DISTINCT cuq.QuestionId) >= 2 -- Ensure the user has at least two qualifying questions in the result set
    AND SUM(CASE WHEN cuq.UniqueEditorsBesidesOwner > 0 THEN 1 ELSE 0 END) >= 1 -- At least one question edited by others
ORDER BY
    DetailedUserCategory DESC, cuq.Reputation DESC, RankInTagByQuestionPerformance ASC
LIMIT 5000;
