-- {"query": "1588.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2414} 
WITH UserActivitySummary AS (
    -- CTE 1: Summarizes user activity, including total questions/answers, average scores, and question edit counts.
    -- Users must have at least one question and one answer to be included here.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0) AS AvgAnswerScore,
        COUNT(DISTINCT PH_Q_Edit.Id) AS QuestionEditCount,
        MAX(U.LastAccessDate) AS UserLastAccessDate
    FROM Users U
    INNER JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN PostHistory PH_Q_Edit ON P.Id = PH_Q_Edit.PostId
        AND P.PostTypeId = 1 -- Only count edits for questions
        AND PH_Q_Edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    GROUP BY U.Id, U.DisplayName
    HAVING SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) >= 1
       AND SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) >= 1
),
UserFilteredActivity AS (
    -- CTE 2: Filters users based on specific performance criteria derived from UserActivitySummary.
    -- Requires average answer score to be higher than average question score, and at least 2 question edits.
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.AvgQuestionScore,
        UAS.AvgAnswerScore,
        UAS.QuestionEditCount,
        UAS.UserLastAccessDate
    FROM UserActivitySummary UAS
    WHERE UAS.AvgAnswerScore > UAS.AvgQuestionScore
      AND UAS.QuestionEditCount >= 2
),
RecentGoldBadges AS (
    -- CTE 3: Identifies the most recent 'Gold' badge for each user.
    -- Uses a window function to rank badges by date.
    SELECT
        B.UserId,
        B.Name AS GoldBadgeName,
        B.Date AS GoldBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC, B.Id DESC) AS rn
    FROM Badges B
    WHERE B.Class = 1 -- Gold badges (1 = Gold, 2 = Silver, 3 = Bronze)
),
CommentScoreOnOthersPosts AS (
    -- CTE 4: Calculates the total score of comments made by users on posts *not* owned by themselves.
    -- Demonstrates filtering and aggregation.
    SELECT
        C.UserId,
        SUM(C.Score) AS TotalCommentScoreOnOthers
    FROM Comments C
    INNER JOIN Posts P ON C.PostId = P.Id
    WHERE C.UserId IS NOT NULL
      AND C.UserId <> P.OwnerUserId -- Comment on someone else's post
    GROUP BY C.UserId
),
DuplicateAndReopenedQuestions AS (
    -- CTE 5: Identifies questions that were initially closed as duplicates and later reopened.
    -- Involves joining PostHistory multiple times and complex string parsing for 'OriginalQuestionIds'.
    SELECT
        PH_Closed.PostId,
        PH_Closed.CreationDate AS ClosedDate,
        PH_Reopened.CreationDate AS ReopenedDate,
        REPLACE(REPLACE(
            SUBSTRING(
                PH_Closed.Text FROM 'OriginalQuestionIds":\[([0-9, ]+)\]'
            ), '[', ''), ']', '') AS OriginalDuplicateQuestionIds -- PostgreSQL specific regex extraction
    FROM PostHistory PH_Closed
    WHERE PH_Closed.PostHistoryTypeId = 10 -- Post Closed
      AND PH_Closed.Comment LIKE '101%' -- Assuming '101' indicates a duplicate close reason
      AND EXISTS (
            SELECT 1
            FROM PostHistory PH_Reopened
            WHERE PH_Reopened.PostId = PH_Closed.PostId
              AND PH_Reopened.PostHistoryTypeId = 11 -- Post Reopened
              AND PH_Reopened.CreationDate > PH_Closed.CreationDate -- Must be reopened *after* being closed
      )
),
UserTaggedQuestions AS (
    -- CTE 6: Prepares question data for selected users, processing tags and ranking by view count.
    -- Includes an outer join to identify questions linked as duplicates.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Title,
        P.ViewCount,
        P.CreationDate,
        P.Score,
        -- Complex string expression to clean and extract tags
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
            THEN SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2) -- Remove leading/trailing '<>'
            ELSE NULL
        END AS ProcessedTags,
        PL.RelatedPostId AS LinkedDuplicatePostId, -- NULL if not linked as duplicate
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.ViewCount DESC, P.Id DESC) AS rn_view
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId AND PL.LinkTypeId = 3 -- LinkType 3 = Duplicate
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.ClosedDate IS NULL -- Not currently closed
)
-- Main query: Combines all CTEs to generate a comprehensive report for the filtered users.
SELECT
    UFA.UserId,
    UFA.DisplayName AS UserName,
    UFA.AvgQuestionScore,
    UFA.AvgAnswerScore,
    UFA.QuestionEditCount,
    UFA.UserLastAccessDate,
    RGB.GoldBadgeName,
    RGB.GoldBadgeDate,
    COALESCE(CSOP.TotalCommentScoreOnOthers, 0) AS UserTotalCommentScoreOnOthersPosts,
    -- Aggregates top 3 most viewed questions that are linked as duplicates, as a formatted string.
    STRING_AGG(CASE WHEN UTQ.rn_view <= 3 AND UTQ.LinkedDuplicatePostId IS NOT NULL THEN
        CONCAT(
            'Q_ID:', UTQ.PostId,
            '|Title:', SUBSTRING(UTQ.Title, 1, 50), -- Truncate title for brevity
            '|Views:', UTQ.ViewCount,
            '|Dupl_Linked_To:', COALESCE(UTQ.LinkedDuplicatePostId::varchar, 'N/A')
        )
    ELSE NULL END, ' ; ') FILTER (WHERE UTQ.rn_view <= 3 AND UTQ.LinkedDuplicatePostId IS NOT NULL) AS Top3LinkedDuplicateQuestions,
    -- Scalar subquery to get tags of the single most viewed question (if it exists and is linked as duplicate).
    COALESCE((
        SELECT UTQ_Inner.ProcessedTags
        FROM UserTaggedQuestions UTQ_Inner
        WHERE UTQ_Inner.OwnerUserId = UFA.UserId
          AND UTQ_Inner.rn_view = 1
          AND UTQ_Inner.LinkedDuplicatePostId IS NOT NULL
        LIMIT 1 -- Ensures a single result in case of ties
    ), 'N/A') AS MostViewedQuestionTags,
    -- Correlated subquery to check if the user has answered their own most viewed question within 30 days of last access, with a minimum score.
    CASE WHEN EXISTS (
        SELECT 1
        FROM Posts P_Answer
        WHERE P_Answer.ParentId = (SELECT UTQ_Inner.PostId FROM UserTaggedQuestions UTQ_Inner WHERE UTQ_Inner.OwnerUserId = UFA.UserId AND UTQ_Inner.rn_view = 1 AND UTQ_Inner.LinkedDuplicatePostId IS NOT NULL LIMIT 1)
          AND P_Answer.OwnerUserId = UFA.UserId
          AND P_Answer.CreationDate < (UFA.UserLastAccessDate + INTERVAL '30 days')
          AND P_Answer.Score > 5 -- Arbitrary score threshold for "good" answer
    ) THEN 'YES' ELSE 'NO' END AS AnsweredOwnTopQuestionWithinWindow,
    -- Aggregates details of questions owned by the user that were closed as duplicates and later reopened.
    ARRAY_AGG(DISTINCT
        CONCAT(
            'DRQ_ID:', DRQ.PostId,
            '|Closed:', DRQ.ClosedDate::date,
            '|Reopened:', DRQ.ReopenedDate::date,
            '|Original_Dupl_IDs:', COALESCE(DRQ.OriginalDuplicateQuestionIds, 'N/A')
        )
    ) FILTER (WHERE P_DRQ.OwnerUserId = UFA.UserId AND DRQ.PostId IS NOT NULL) AS DuplicateReopenedQuestionDetails,
    COUNT(DISTINCT DRQ.PostId) FILTER (WHERE P_DRQ.OwnerUserId = UFA.UserId AND DRQ.PostId IS NOT NULL) AS TotalDuplicateReopenedQuestionsByThisUser
FROM UserFilteredActivity UFA
LEFT JOIN RecentGoldBadges RGB ON UFA.UserId = RGB.UserId AND RGB.rn = 1
LEFT JOIN CommentScoreOnOthersPosts CSOP ON UFA.UserId = CSOP.UserId
LEFT JOIN UserTaggedQuestions UTQ ON UFA.UserId = UTQ.OwnerUserId
-- Join Posts to link DuplicateAndReopenedQuestions to the owning user
LEFT JOIN Posts P_DRQ ON P_DRQ.OwnerUserId = UFA.UserId AND P_DRQ.PostTypeId = 1
LEFT JOIN DuplicateAndReopenedQuestions DRQ ON P_DRQ.Id = DRQ.PostId
GROUP BY
    UFA.UserId, UFA.DisplayName, UFA.AvgQuestionScore, UFA.AvgAnswerScore,
    UFA.QuestionEditCount, UFA.UserLastAccessDate,
    RGB.GoldBadgeName, RGB.GoldBadgeDate, CSOP.TotalCommentScoreOnOthers
HAVING
    COUNT(CASE WHEN UTQ.rn_view <= 3 AND UTQ.LinkedDuplicatePostId IS NOT NULL THEN UTQ.PostId END) > 0 -- Ensure users selected actually have relevant questions
ORDER BY
    UFA.UserLastAccessDate DESC,
    UFA.AvgAnswerScore DESC;