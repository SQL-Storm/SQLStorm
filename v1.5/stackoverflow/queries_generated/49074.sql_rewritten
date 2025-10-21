-- {"query": "49074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2405} 
WITH InitialFilteredQuestions AS (
    -- Select initial set of potentially interesting questions based on basic metrics and creation date
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score AS QuestionScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.LastEditDate,
        P.LastActivityDate
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1 -- Only questions
        AND P.Score >= 10 -- Minimum score for relevance
        AND P.ViewCount >= 1000 -- Popular questions
        AND P.AnswerCount >= 3 -- Questions with some debate/multiple perspectives
        AND P.CommentCount >= 5 -- Engaged questions
        AND P.CreationDate < '2023-01-01' -- Exclude very recent posts to allow for historical activity
), FilteredQuestionsWithTags AS (
    -- Further filter questions by specific, popular technology tags, using string_to_array for robustness
    SELECT
        IFQ.QuestionId,
        IFQ.OwnerUserId,
        IFQ.CreationDate,
        IFQ.QuestionScore,
        IFQ.ViewCount,
        IFQ.AnswerCount,
        IFQ.CommentCount,
        IFQ.FavoriteCount,
        IFQ.Title,
        IFQ.Tags,
        IFQ.LastEditDate,
        IFQ.LastActivityDate
    FROM
        InitialFilteredQuestions IFQ
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(IFQ.Tags, 2, length(IFQ.Tags)-2), '><')) AS Tag
    WHERE
        Tag IN ('java', 'python', 'javascript', 'c#', 'sql', 'performance', 'database', 'azure', 'aws')
    GROUP BY -- Group back to unique questions after unnesting might duplicate rows per tag
        IFQ.QuestionId, IFQ.OwnerUserId, IFQ.CreationDate, IFQ.QuestionScore, IFQ.ViewCount,
        IFQ.AnswerCount, IFQ.CommentCount, IFQ.FavoriteCount, IFQ.Title, IFQ.Tags,
        IFQ.LastEditDate, IFQ.LastActivityDate
), QuestionActivity AS (
    -- Analyze activity for each filtered question, including comments/answers within the first year, edits, and close/reopen events
    SELECT
        FQ.QuestionId,
        FQ.OwnerUserId,
        FQ.CreationDate,
        FQ.QuestionScore,
        FQ.ViewCount,
        FQ.AnswerCount,
        FQ.CommentCount,
        FQ.FavoriteCount,
        FQ.Title,
        FQ.Tags,
        FQ.LastEditDate,
        FQ.LastActivityDate,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT ANS.Id) AS TotalAnswers,
        COUNT(DISTINCT CASE WHEN C.CreationDate BETWEEN FQ.CreationDate AND (FQ.CreationDate + INTERVAL '1 year') THEN C.Id END) AS CommentsFirstYear,
        COUNT(DISTINCT CASE WHEN ANS.CreationDate BETWEEN FQ.CreationDate AND (FQ.CreationDate + INTERVAL '1 year') THEN ANS.Id END) AS AnswersFirstYear,
        COUNT(DISTINCT PH_Edit.Id) AS TotalEdits,
        COUNT(DISTINCT PH_Close.Id) AS CloseEvents,
        COUNT(DISTINCT PH_Reopen.Id) AS ReopenEvents,
        COUNT(DISTINCT PL_Linked.Id) AS LinkedPosts,
        COUNT(DISTINCT PL_Duplicate.Id) AS DuplicatePosts
    FROM
        FilteredQuestionsWithTags FQ
    LEFT JOIN
        Comments C ON FQ.QuestionId = C.PostId
    LEFT JOIN
        Posts ANS ON FQ.QuestionId = ANS.ParentId AND ANS.PostTypeId = 2 -- Answers to this question
    LEFT JOIN
        PostHistory PH_Edit ON FQ.QuestionId = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    LEFT JOIN
        PostHistory PH_Close ON FQ.QuestionId = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN
        PostHistory PH_Reopen ON FQ.QuestionId = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11 -- Post Reopened
    LEFT JOIN
        PostLinks PL_Linked ON FQ.QuestionId = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1 -- Linked posts
    LEFT JOIN
        PostLinks PL_Duplicate ON FQ.QuestionId = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3 -- Duplicate posts
    GROUP BY
        FQ.QuestionId, FQ.OwnerUserId, FQ.CreationDate, FQ.QuestionScore, FQ.ViewCount, FQ.AnswerCount, FQ.CommentCount,
        FQ.FavoriteCount, FQ.Title, FQ.Tags, FQ.LastEditDate, FQ.LastActivityDate
), UserQuestionImpact AS (
    -- Aggregate question-centric metrics by the owner user
    SELECT
        QA.OwnerUserId AS UserId,
        COUNT(QA.QuestionId) AS TotalQuestionsContributed,
        SUM(QA.QuestionScore) AS TotalQuestionScore,
        SUM(QA.ViewCount) AS TotalQuestionViews,
        AVG(QA.AnswerCount) AS AvgAnswersPerQuestion,
        AVG(QA.CommentsFirstYear) AS AvgCommentsFirstYear,
        AVG(QA.AnswersFirstYear) AS AvgAnswersFirstYear,
        SUM(QA.TotalEdits) AS TotalEditsOnQuestions,
        SUM(QA.CloseEvents) AS TotalQuestionCloseEvents,
        SUM(QA.ReopenEvents) AS TotalQuestionReopenEvents,
        SUM(QA.LinkedPosts) AS TotalQuestionLinkedPosts,
        SUM(QA.DuplicatePosts) AS TotalQuestionDuplicatePosts,
        MAX(QA.CreationDate) AS LastQuestionCreationDate,
        MIN(QA.CreationDate) AS FirstQuestionCreationDate,
        -- Calculate average days a question remains "active" (from creation to last activity)
        AVG(EXTRACT(EPOCH FROM (QA.LastActivityDate - QA.CreationDate))/3600/24) AS AvgDaysActiveSinceCreation
    FROM
        QuestionActivity QA
    GROUP BY
        QA.OwnerUserId
    HAVING
        COUNT(QA.QuestionId) >= 3 -- Only consider users with at least 3 qualifying questions
), UserOverallActivity AS (
    -- Gather overall user statistics including reputation, badges, and answer contributions
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.Views AS ProfileViews,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.TagBased = TRUE THEN B.Id END) AS TagBasedBadges,
        COUNT(DISTINCT P_Ans.Id) AS TotalAnswersPosted,
        SUM(P_Ans.Score) AS TotalAnswerScore,
        AVG(P_Ans.Score) AS AvgAnswerScore
    FROM
        Users U
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        Posts P_Ans ON U.Id = P_Ans.OwnerUserId AND P_Ans.PostTypeId = 2 -- Answers by this user
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views, U.CreationDate
)
-- Final selection and ranking of users based on a composite impact score
SELECT
    UOI.UserId,
    UOI.DisplayName,
    UOI.Reputation,
    UQI.TotalQuestionsContributed,
    UQI.TotalQuestionScore,
    UQI.TotalQuestionViews,
    UQI.TotalEditsOnQuestions,
    UQI.TotalQuestionCloseEvents,
    UQI.TotalQuestionReopenEvents,
    UQI.AvgDaysActiveSinceCreation,
    UOI.TotalBadges,
    UOI.GoldBadges,
    UOI.TagBasedBadges,
    UOI.TotalAnswersPosted,
    UOI.TotalAnswerScore,
    RANK() OVER (ORDER BY
        -- Complex scoring formula to weigh different aspects of user impact
        (UQI.TotalQuestionScore * 0.4 +                         -- Weight for score of owned questions
         UQI.TotalQuestionViews * 0.001 +                       -- Weight for views on owned questions
         UQI.AvgAnswersPerQuestion * 10 +                       -- Weight for average answers per question
         UQI.AvgCommentsFirstYear * 5 +                         -- Weight for initial comments
         UQI.AvgAnswersFirstYear * 15 +                         -- Weight for initial answers
         UQI.TotalEditsOnQuestions * 2 +                        -- Weight for maintaining/improving owned questions
         (UQI.TotalQuestionReopenEvents - UQI.TotalQuestionCloseEvents) * 50 + -- Reward reopens, penalize closes
         UQI.TotalQuestionLinkedPosts * 5 +                     -- Reward for linking questions
         UQI.TotalQuestionDuplicatePosts * -10 +                -- Minor penalty for creating duplicates
         UQI.AvgDaysActiveSinceCreation * 0.1 +                 -- Reward for long-lived questions
         UOI.Reputation * 0.01 +                                -- Incorporate overall user reputation
         UOI.TotalBadges * 10 +                                 -- Reward for total badges
         UOI.GoldBadges * 50 +                                  -- Higher reward for gold badges
         UOI.TagBasedBadges * 20 +                              -- Reward for tag-specific expertise
         UOI.TotalAnswerScore * 0.1                             -- Reward for overall answer contributions
        ) DESC
    ) AS OverallImpactRank
FROM
    UserQuestionImpact UQI
JOIN
    UserOverallActivity UOI ON UQI.UserId = UOI.UserId
WHERE
    UOI.Reputation > 1000 -- Only consider established users for final ranking
ORDER BY
    OverallImpactRank
LIMIT 100;