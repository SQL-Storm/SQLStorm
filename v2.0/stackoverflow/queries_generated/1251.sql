-- {"query": "1251.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3086} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END), 0) AS AvgQuestionViews,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Calculate the reputation rank among all users, partitioned by creation year
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS AnnualReputationRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
QuestionMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.OwnerUserId,
        q.LastEditDate,
        q.LastActivityDate,
        q.AcceptedAnswerId,
        q.FavoriteCount,
        COALESCE(q.AnswerCount, 0) AS DirectAnswerCount,
        ph_closed.Comment AS CloseReasonIdText,
        crt.Name AS CloseReasonName,
        -- Correlated subquery to count comments for this specific question
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = q.Id AND c.CreationDate > q.CreationDate - INTERVAL '1 month') AS RecentCommentCount,
        -- Correlated subquery to find the date of the last edit by a user other than the original owner
        (SELECT MAX(ph_edit.CreationDate)
         FROM PostHistory ph_edit
         WHERE ph_edit.PostId = q.Id
           AND ph_edit.PostHistoryTypeId IN (4,5,6) -- Edit Title, Edit Body, Edit Tags
           AND ph_edit.UserId IS NOT NULL
           AND ph_edit.UserId <> q.OwnerUserId
        ) AS LastOtherUserEditDate,
        -- Parse tags into an array, handling potential NULL or empty tag strings
        STRING_TO_ARRAY(COALESCE(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), ''), '><') AS ParsedTags,
        -- Correlated subquery to count duplicate links for this question
        (SELECT COUNT(DISTINCT pl.RelatedPostId)
         FROM PostLinks pl
         WHERE pl.PostId = q.Id
           AND pl.LinkTypeId = 3 -- Duplicate link type
        ) AS DuplicateCount,
        -- Correlated subquery to sum bounty amounts for this question
        (SELECT SUM(v.BountyAmount)
         FROM Votes v
         WHERE v.PostId = q.Id AND v.VoteTypeId = 8 -- BountyStart vote type
        ) AS TotalBountyAmount,
        -- Estimated reputation change for the question owner based on votes on this question (simplified logic)
        (SELECT COALESCE(SUM(CASE
                                WHEN v.VoteTypeId = 2 THEN 10 -- Upvote on question
                                WHEN v.VoteTypeId = 3 THEN -2 -- Downvote on question
                                ELSE 0
                             END), 0)
         FROM Votes v
         WHERE v.PostId = q.Id
        ) AS EstimatedQuestionRepChange
    FROM
        Posts q
    LEFT JOIN
        PostHistory ph_closed ON q.Id = ph_closed.PostId AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN
        CloseReasonTypes crt ON ph_closed.Comment = crt.Id::varchar -- Join on Id string representation
    WHERE
        q.PostTypeId = 1 -- Only questions
),
AnswerSummary AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS ActualAnswerCount,
        COALESCE(AVG(a.Score), 0) AS AvgAnswerScore,
        -- Score of the accepted answer, if any
        MAX(CASE WHEN a.Id = qm.AcceptedAnswerId THEN a.Score ELSE 0 END) AS AcceptedAnswerScore,
        -- Rank answers by score for each question using a window function
        COALESCE(MAX(a.Score) OVER (PARTITION BY a.ParentId), 0) AS TopAnswerScore,
        -- Latest creation date among answers for a question, using a window function
        MAX(a.CreationDate) OVER (PARTITION BY a.ParentId) AS LatestAnswerDate
    FROM
        Posts a
    INNER JOIN
        QuestionMetrics qm ON a.ParentId = qm.QuestionId -- Join answers to their questions
    WHERE
        a.PostTypeId = 2 -- Only answers
    GROUP BY
        a.ParentId, qm.AcceptedAnswerId
),
TagPerformance AS (
    SELECT
        unnest(qm.ParsedTags) AS TagName,
        COUNT(qm.QuestionId) AS TotalQuestionsWithTag,
        AVG(qm.QuestionScore) AS AvgQuestionScoreForTag,
        AVG(qm.QuestionViewCount) AS AvgQuestionViewCountForTag,
        -- Calculate a composite engagement score for each tag
        (AVG(qm.QuestionScore) * 0.6 + AVG(qm.QuestionViewCount) * 0.4) AS TagEngagementScore,
        -- Rank tags by their engagement score
        RANK() OVER (ORDER BY (AVG(qm.QuestionScore) * 0.6 + AVG(qm.QuestionViewCount) * 0.4) DESC) AS TagEngagementRank
    FROM
        QuestionMetrics qm
    WHERE array_length(qm.ParsedTags, 1) > 0 -- Exclude questions without tags
    GROUP BY
        unnest(qm.ParsedTags)
),
UserActivityRank AS (
    SELECT
        UserId,
        UserName,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        OverallPostRank,
        ReputationDensityRank,
        PrevRepUserPostsInMonth,
        AnnualReputationRank,
        LAG(Reputation, 1, 0) OVER (ORDER BY Reputation DESC) AS ReputationOfPrevUser
    FROM (
        SELECT
            UserId,
            UserName,
            Reputation,
            TotalPosts,
            TotalQuestions,
            TotalAnswers,
            ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) AS OverallPostRank,
            DENSE_RANK() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS ReputationDensityRank,
            LAG(TotalPosts, 1, 0) OVER (PARTITION BY DATE_TRUNC('month', UserCreationDate) ORDER BY Reputation DESC) AS PrevRepUserPostsInMonth,
            AnnualReputationRank
        FROM UserEngagement
        WHERE TotalPosts > 0
    ) AS SubUserActivity
)
SELECT
    uar.UserId,
    uar.UserName,
    uar.Reputation,
    uar.TotalQuestions,
    uar.TotalAnswers,
    uar.AvgPostScore,
    uar.AvgQuestionViews,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    uar.AnnualReputationRank,
    uar.ReputationOfPrevUser,
    qm.QuestionId,
    qm.QuestionTitle,
    qm.QuestionScore,
    qm.QuestionViewCount,
    qm.QuestionCreationDate,
    qm.DirectAnswerCount,
    asum.ActualAnswerCount,
    asum.AvgAnswerScore,
    asum.AcceptedAnswerScore,
    asum.TopAnswerScore,
    asum.LatestAnswerDate,
    qm.RecentCommentCount,
    qm.DuplicateCount,
    qm.TotalBountyAmount,
    qm.EstimatedQuestionRepChange,
    COALESCE(qm.CloseReasonName, 'Open') AS QuestionStatus,
    CASE WHEN qm.AcceptedAnswerId IS NOT NULL THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer,
    qm.LastOtherUserEditDate,
    dt.DominantTagName,
    tp.TagEngagementScore,
    tp.TagEngagementRank,
    uar.OverallPostRank,
    uar.ReputationDensityRank,
    uar.PrevRepUserPostsInMonth,
    -- Complex calculation: overall question impact score combining user reputation, post metrics, and tag performance
    (uar.Reputation / 1000.0) * (qm.QuestionScore + asum.AvgAnswerScore) * (1 + COALESCE(qm.FavoriteCount, 0) / 5.0) * (1 + (tp.TagEngagementRank / 1000.0)) AS OverallQuestionImpactScore,
    -- String expression: a modified snippet of the question title
    UPPER(LEFT(COALESCE(qm.QuestionTitle, 'Untitled'), 5)) || '...' || LOWER(RIGHT(COALESCE(qm.QuestionTitle, 'Untitled'), 5)) AS TitleSnippet,
    -- NULL logic and date calculations
    COALESCE(qm.LastOtherUserEditDate, qm.LastActivityDate, qm.QuestionCreationDate) AS EffectiveLastInteractionDate,
    (EXTRACT(EPOCH FROM (NOW() - qm.QuestionCreationDate)) / (60 * 60 * 24 * 365.25))::numeric(5,2) AS QuestionAgeYears,
    -- Complex conditional categorization of questions
    CASE
        WHEN qm.QuestionScore > 75 AND asum.AvgAnswerScore > 15 AND COALESCE(qm.FavoriteCount, 0) > 10 THEN 'Highly Valued & Popular'
        WHEN qm.QuestionScore BETWEEN 20 AND 75 AND asum.ActualAnswerCount > 5 AND qm.AcceptedAnswerId IS NOT NULL THEN 'Well Answered & Engaging'
        WHEN qm.CloseReasonName IS NOT NULL AND qm.CloseReasonName ILIKE '%Duplicate%' AND qm.DuplicateCount > 0 THEN 'Closed as Established Duplicate'
        WHEN qm.TotalBountyAmount IS NOT NULL AND qm.TotalBountyAmount > 0 AND asum.AcceptedAnswerScore > 0 THEN 'Bountied & Solved'
        WHEN qm.QuestionCreationDate < NOW() - INTERVAL '3 years' AND qm.LastOtherUserEditDate IS NULL AND qm.RecentCommentCount = 0 THEN 'Stale Question'
        ELSE 'General Interest'
    END AS QuestionCategory
FROM
    UserActivityRank uar
INNER JOIN
    QuestionMetrics qm ON uar.UserId = qm.OwnerUserId
LEFT JOIN
    AnswerSummary asum ON qm.QuestionId = asum.QuestionId
LEFT JOIN LATERAL
    (SELECT t.TagName_Candidate AS DominantTagName
     FROM unnest(qm.ParsedTags) AS t(TagName_Candidate)
     JOIN TagPerformance tp_inner ON t.TagName_Candidate = tp_inner.TagName
     ORDER BY tp_inner.TagEngagementScore DESC, t.TagName_Candidate -- Pick the tag with the highest engagement score for this question
     LIMIT 1
    ) AS dt ON TRUE
LEFT JOIN
    TagPerformance tp ON dt.DominantTagName = tp.TagName
WHERE
    uar.Reputation > 2500 -- Filter for more experienced users
    AND qm.QuestionViewCount > 500 -- Filter for questions with significant visibility
    AND qm.QuestionCreationDate >= NOW() - INTERVAL '3 years' -- Focus on relatively recent questions
    AND array_length(qm.ParsedTags, 1) > 0 -- Ensure question has tags
    AND (qm.QuestionTitle ILIKE '%optimize%' OR qm.QuestionTitle ILIKE '%performance%' OR qm.QuestionTitle ILIKE '%tuning%') -- Specific topic search
    -- Complex NULL logic and conditional filtering for question quality
    AND (
        (qm.AcceptedAnswerId IS NOT NULL AND asum.AvgAnswerScore > 10 AND qm.FavoriteCount IS NOT NULL AND qm.FavoriteCount > 2) -- Highly accepted and favorited
        OR
        (qm.AcceptedAnswerId IS NULL AND qm.DirectAnswerCount > 5 AND qm.QuestionScore > 30 AND qm.CloseReasonName IS NULL) -- Highly answered but not accepted, high score, and not closed
        OR
        (qm.CloseReasonName IS NOT NULL AND qm.CloseReasonName NOT ILIKE '%Off-topic%' AND qm.QuestionScore > 10) -- Closed for valid reason, but still has some value
    )
ORDER BY
    OverallQuestionImpactScore DESC,
    uar.Reputation DESC,
    qm.QuestionCreationDate DESC
LIMIT 1000;
