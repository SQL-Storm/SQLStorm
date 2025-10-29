-- {"query": "1993.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3469} 

WITH UserAggregatedStats AS (
    -- CTE 1: Gathers foundational user statistics, including reputation, total posts, questions, answers, badges, and activity dates.
    -- Utilizes LEFT JOINs to include users even if they have no posts or badges, and aggregates counts and sums.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore, -- NULL logic: COALESCE for sum of scores
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews, -- NULL logic: COALESCE for sum of views
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostHistoricalMetrics AS (
    -- CTE 2: Captures detailed post metrics, including edit counts, closure reasons, and status.
    -- Joins with PostHistory to count edits and extract close reasons using conditional aggregation and CAST.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.ParentId, -- ParentId is essential for answers to link to their questions
        P.AcceptedAnswerId,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END), 0) AS ContentEditCount, -- Calculates number of content-related edits
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastClosedHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL THEN CRT.Name END) AS LatestCloseReasonName -- Extracts the name of the last close reason
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    -- Complex join for CloseReasonTypes, assuming PH.Comment can be cast to smallint when PostHistoryTypeId is 10
    LEFT JOIN CloseReasonTypes AS CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CRT.Id = CAST(PH.Comment AS smallint)
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.ClosedDate,
        P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.Title, P.Tags, P.ParentId, P.AcceptedAnswerId
),
PostLinkSummary AS (
    -- CTE 3: Summarizes incoming and outgoing links for each post, distinguishing duplicate links.
    -- Uses LEFT JOINs on PostLinks to count both PostId and RelatedPostId instances.
    SELECT
        P.Id AS PostId,
        COALESCE(COUNT(DISTINCT PL_OUT.RelatedPostId), 0) AS TotalLinksOut,
        COALESCE(COUNT(DISTINCT PL_IN.PostId), 0) AS TotalLinksIn,
        COALESCE(SUM(CASE WHEN PL_OUT.LinkTypeId = 3 THEN 1 ELSE 0 END), 0) AS DuplicateLinksOut,
        COALESCE(SUM(CASE WHEN PL_IN.LinkTypeId = 3 THEN 1 ELSE 0 END), 0) AS DuplicateLinksIn
    FROM Posts AS P
    LEFT JOIN PostLinks AS PL_OUT ON P.Id = PL_OUT.PostId
    LEFT JOIN PostLinks AS PL_IN ON P.Id = PL_IN.RelatedPostId
    GROUP BY P.Id
),
CommentActivity AS (
    -- CTE 4: Aggregates comment statistics for posts, including total comments and comments made by the post owner.
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        COUNT(CASE WHEN C.UserId = P.OwnerUserId THEN 1 ELSE 0 END) AS OwnerCommentsOnPost, -- Counts comments made by the post's owner
        MAX(C.CreationDate) AS LatestCommentDate
    FROM Comments AS C
    JOIN Posts AS P ON C.PostId = P.Id
    GROUP BY C.PostId
),
RankedProblematicPosts AS (
    -- CTE 5: Identifies and ranks "problematic" questions based on negative score, high edit count, or closure.
    -- Includes complex calculations, correlated subqueries, window functions, and string/date manipulations.
    SELECT
        'Controversial_Question' AS ReportCategory,
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        PHM.PostId,
        PHM.Title,
        PHM.PostCreationDate,
        PHM.Score AS PostScore,
        PHM.ViewCount AS PostViews,
        PHM.ContentEditCount,
        PHM.TotalHistoryEntries,
        PHM.LatestCloseReasonName AS PrimaryReason,
        COALESCE(PLS.TotalLinksIn, 0) AS IncomingLinks,
        COALESCE(PLS.DuplicateLinksIn, 0) AS IncomingDuplicateLinks,
        COALESCE(CAS.OwnerCommentsOnPost, 0) AS OwnerComments,
        -- Complicated calculation: "Problematicity Score" combining edits, negative score, and closure status
        (CAST(PHM.ContentEditCount AS DECIMAL) * 5) +
        (CASE WHEN PHM.Score < 0 THEN ABS(PHM.Score) * 2 ELSE 0 END) +
        (CASE WHEN PHM.ClosedDate IS NOT NULL THEN 10 ELSE 0 END) -
        (COALESCE(PLS.TotalLinksIn, 0) * 0.5) AS ProblematicityScore,
        -- Window function: Ranks posts by 'volatility' (edits per view) within a user's questions
        RANK() OVER (PARTITION BY UAS.UserId ORDER BY CAST(PHM.ContentEditCount AS DECIMAL) / NULLIF(PHM.ViewCount, 0) DESC NULLS LAST) AS RankInSubcategory,
        -- String expression and NULL logic: Extracts the first tag from the Tags string, or 'No Tag'
        COALESCE(SPLIT_PART(SUBSTRING(PHM.Tags FROM 2 FOR LENGTH(PHM.Tags) - 2), '><', 1), 'No Tag') AS MainTag,
        -- Correlated Subquery: Checks if the post owner has a 'Reversal' badge, indicating they reopen posts
        EXISTS (
            SELECT 1
            FROM Badges AS B
            WHERE B.UserId = UAS.UserId
              AND B.Name = 'Reversal'
        ) AS HasSpecialBadge,
        -- Date calculation: Age of post in days until closure, or until current date if not closed
        EXTRACT(DAY FROM (COALESCE(PHM.ClosedDate, NOW()) - PHM.PostCreationDate)) AS AgeAtStatusChange,
        -- Window function: Categorizes posts into 5 groups based on their problematicity score
        NTILE(5) OVER (ORDER BY (
            (CAST(PHM.ContentEditCount AS DECIMAL) * 5) +
            (CASE WHEN PHM.Score < 0 THEN ABS(PHM.Score) * 2 ELSE 0 END) +
            (CASE WHEN PHM.ClosedDate IS NOT NULL THEN 10 ELSE 0 END) -
            (COALESCE(PLS.TotalLinksIn, 0) * 0.5)
        ) DESC) AS ScoreQuintileGroup
    FROM UserAggregatedStats AS UAS
    JOIN PostHistoricalMetrics AS PHM ON UAS.UserId = PHM.OwnerUserId
    LEFT JOIN PostLinkSummary AS PLS ON PHM.PostId = PLS.PostId
    LEFT JOIN CommentActivity AS CAS ON PHM.PostId = CAS.PostId
    WHERE PHM.PostTypeId = 1 -- Focus on questions
      AND (PHM.Score < -2 OR PHM.ContentEditCount > 3 OR PHM.ClosedDate IS NOT NULL) -- Filter for problematic posts
      AND UAS.TotalQuestions > 1 -- Only consider users who have asked multiple questions
      AND NOT EXISTS ( -- Correlated Subquery: Excludes questions marked as duplicates of high-scoring questions
            SELECT 1
            FROM PostLinks AS PL_DUP
            JOIN Posts AS P_DUP ON PL_DUP.RelatedPostId = P_DUP.Id
            WHERE PL_DUP.PostId = PHM.PostId
              AND PL_DUP.LinkTypeId = 3 -- Identifies duplicate links
              AND P_DUP.Score > 5 -- Original question has a good score
          )
      AND (PHM.PostCreationDate > NOW() - INTERVAL '3 year' AND PHM.LastActivityDate > NOW() - INTERVAL '1 year') -- Posts with recent activity
),
RankedHighPerformingAnswers AS (
    -- CTE 6: Identifies and ranks high-performing answers based on score, favorites, and acceptance status.
    -- Similar constructs to CTE 5 but tailored for answers.
    SELECT
        'High_Performing_Answer' AS ReportCategory,
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        PHM.PostId,
        COALESCE(P_Q.Title, 'No Parent Question Title') AS Title, -- Gets the title of the parent question
        PHM.PostCreationDate,
        PHM.Score AS PostScore,
        PHM.ViewCount AS PostViews,
        PHM.ContentEditCount,
        PHM.TotalHistoryEntries,
        NULL AS PrimaryReason, -- Answers typically don't have close reasons
        COALESCE(PLS.TotalLinksIn, 0) AS IncomingLinks,
        COALESCE(PLS.DuplicateLinksIn, 0) AS IncomingDuplicateLinks,
        COALESCE(CAS.OwnerCommentsOnPost, 0) AS OwnerComments,
        -- Complicated calculation: "Answer Impact Score" combining score, favorites, and accepted status
        (CAST(PHM.Score AS DECIMAL) * 1.5) + (PHM.FavoriteCount * 3) +
        (CASE WHEN PHM.AcceptedAnswerId = PHM.PostId THEN 20 ELSE 0 END) - -- Bonus for accepted answer
        (CAST(PHM.ContentEditCount AS DECIMAL) * 0.5) AS AnswerImpactScore,
        -- Window function: Ranks answers by their impact score within a user's answers
        RANK() OVER (PARTITION BY UAS.UserId ORDER BY (
            (CAST(PHM.Score AS DECIMAL) * 1.5) + (PHM.FavoriteCount * 3) +
            (CASE WHEN PHM.AcceptedAnswerId = PHM.PostId THEN 20 ELSE 0 END) -
            (CAST(PHM.ContentEditCount AS DECIMAL) * 0.5)
        ) DESC) AS RankInSubcategory,
        -- String expression and NULL logic: Extracts the first tag from the parent question's Tags
        COALESCE(SPLIT_PART(SUBSTRING(P_Q.Tags FROM 2 FOR LENGTH(P_Q.Tags) - 2), '><', 1), 'No Tag') AS MainTag,
        -- Correlated Subquery: Checks if the answer owner has specific gold badges for answers/comments
        EXISTS (
            SELECT 1
            FROM Badges AS B
            WHERE B.UserId = UAS.UserId
              AND B.Class = 1 -- Gold badges
              AND B.Name IN ('Enlightened', 'Great Answer', 'Pundit')
        ) AS HasSpecialBadge,
        -- Date calculation: Age of answer in days
        EXTRACT(DAY FROM (NOW() - PHM.PostCreationDate)) AS AgeAtStatusChange,
        -- Window function: Categorizes answers into 5 groups based on their impact score
        NTILE(5) OVER (ORDER BY (
            (CAST(PHM.Score AS DECIMAL) * 1.5) + (PHM.FavoriteCount * 3) +
            (CASE WHEN PHM.AcceptedAnswerId = PHM.PostId THEN 20 ELSE 0 END) -
            (CAST(PHM.ContentEditCount AS DECIMAL) * 0.5)
        ) DESC) AS ScoreQuintileGroup
    FROM UserAggregatedStats AS UAS
    JOIN PostHistoricalMetrics AS PHM ON UAS.UserId = PHM.OwnerUserId
    JOIN Posts AS P_Q ON PHM.PostTypeId = 2 AND P_Q.Id = PHM.ParentId -- Joins to the parent question
    LEFT JOIN PostLinkSummary AS PLS ON PHM.PostId = PLS.PostId
    LEFT JOIN CommentActivity AS CAS ON PHM.PostId = CAS.PostId
    WHERE PHM.PostTypeId = 2 -- Focus on answers
      AND PHM.Score > 5 -- Filter for high-scoring answers
      AND PHM.AcceptedAnswerId = PHM.PostId -- Must be an accepted answer
      AND UAS.TotalAnswers > 2 -- Only consider users who have posted multiple answers
      AND EXISTS ( -- Correlated Subquery: Checks if the parent question has at least 2 answers
            SELECT 1
            FROM Posts AS P_ANS_COUNT
            WHERE P_ANS_COUNT.Id = PHM.ParentId
              AND COALESCE(P_ANS_COUNT.AnswerCount, 0) >= 2
          )
      AND (
            -- Correlated Subquery: Checks for at least one favorite vote on the answer
            SELECT COUNT(V.Id)
            FROM Votes AS V
            WHERE V.PostId = PHM.PostId
              AND V.VoteTypeId = 5 -- Favorite votes
              AND V.CreationDate BETWEEN PHM.PostCreationDate AND NOW()
          ) >= 1
)
-- Main query using UNION ALL to combine "problematic questions" and "high-performing answers"
SELECT *
FROM RankedProblematicPosts
WHERE ProblematicityScore > 10 -- Final filter on the calculated problematicity score
UNION ALL
SELECT *
FROM RankedHighPerformingAnswers
WHERE AnswerImpactScore > 15 -- Final filter on the calculated answer impact score
ORDER BY Reputation DESC, PostScore DESC
LIMIT 1000; -- Limits the final result set for benchmarking purposes
