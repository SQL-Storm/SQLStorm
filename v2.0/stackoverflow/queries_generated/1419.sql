-- {"query": "1419.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3316} 

WITH UserOverallStats AS (
    -- Aggregates user-specific data like post counts, total scores, reputation, and specific badge counts.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        MAX(P.LastActivityDate) AS LastPostActivity,
        -- Using FILTER (WHERE) for conditional aggregation
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadgesCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadgesCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadgesCount,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionDetailedMetrics AS (
    -- Gathers specific metrics for questions, including comment statistics, bounty info, and linked posts.
    SELECT
        Q.Id AS QuestionId,
        Q.AcceptedAnswerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        Q.AnswerCount,
        Q.CommentCount AS InitialCommentCount,
        Q.FavoriteCount,
        Q.Title AS QuestionTitle,
        Q.Body AS QuestionBody,
        Q.Tags AS RawTags,
        COALESCE(Q.LastEditDate, Q.CreationDate) AS LastEditOrCreationDate,
        -- String expression to parse tags
        STRING_TO_ARRAY(SUBSTRING(Q.Tags, 2, LENGTH(Q.Tags)-2), '><') AS ParsedTags,
        -- Correlated subquery for max comment score
        (SELECT MAX(C.Score) FROM Comments C WHERE C.PostId = Q.Id) AS MaxCommentScore,
        -- Correlated subquery for unique commenters
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = Q.Id AND C.UserId IS NOT NULL) AS UniqueCommenters,
        -- Correlated subquery for total bounty amount
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId = 8) AS TotalBountyAmount,
        -- Counts for different link types via conditional aggregation
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicateLinkCount,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostCount
    FROM
        Posts Q
    LEFT JOIN PostLinks PL ON Q.Id = PL.PostId
    WHERE
        Q.PostTypeId = 1 -- Only questions
    GROUP BY
        Q.Id, Q.AcceptedAnswerId, Q.CreationDate, Q.ViewCount, Q.Score, Q.AnswerCount, Q.CommentCount, Q.FavoriteCount, Q.Title, Q.Body, Q.Tags, Q.LastEditDate
),
PostLifecycleEvents AS (
    -- Identifies post closure and reopen events, including close reasons.
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PHT.Name AS EventTypeName
    FROM
        PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE
        PH.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
),
ClosedDurationAnalysis AS (
    -- Analyzes the duration posts were closed and identifies if currently closed using a LATERAL JOIN.
    SELECT
        ple_start.PostId,
        MIN(ple_start.EventDate) FILTER (WHERE ple_start.PostHistoryTypeId = 10) AS FirstClosedDate,
        MAX(ple_end_paired.EventDate) FILTER (WHERE ple_end_paired.PostHistoryTypeId = 11) AS LastReopenedDate,
        -- Calculates cumulative closed time, treating currently closed posts as closed until CURRENT_TIMESTAMP
        SUM(EXTRACT(EPOCH FROM (COALESCE(ple_end_paired.EventDate, CURRENT_TIMESTAMP) - ple_start.EventDate))) AS TotalSecondsClosed_Estimate,
        BOOL_OR(ple_start.PostHistoryTypeId = 10) AS WasEverClosed,
        -- Checks if the post is currently closed (a close event without a subsequent reopen)
        BOOL_OR(ple_start.PostHistoryTypeId = 10 AND ple_end_paired.EventDate IS NULL) AS IsCurrentlyClosed
    FROM
        PostLifecycleEvents ple_start
    LEFT JOIN LATERAL ( -- Correlated subquery (LATERAL JOIN) to find the next corresponding reopen event for each close event
        SELECT ple_end_inner.EventDate, ple_end_inner.PostHistoryTypeId
        FROM PostLifecycleEvents ple_end_inner
        WHERE ple_end_inner.PostId = ple_start.PostId
          AND ple_end_inner.PostHistoryTypeId = 11 -- Reopened event
          AND ple_end_inner.EventDate > ple_start.EventDate
        ORDER BY ple_end_inner.EventDate
        LIMIT 1
    ) ple_end_paired ON ple_start.PostHistoryTypeId = 10 -- Only consider 'closed' events for duration calculation
    GROUP BY ple_start.PostId
    HAVING BOOL_OR(ple_start.PostHistoryTypeId = 10) -- Only include posts that were actually closed
),
BaseQuestionData AS (
    -- Joins all preceding CTEs and initial Post/User data for questions and their answers.
    SELECT
        Q.QuestionId,
        Q.QuestionTitle,
        Q.QuestionCreationDate,
        Q.QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        UOS.UserId AS OwnerUserId,
        UOS.DisplayName AS OwnerDisplayName,
        UOS.Reputation AS OwnerReputation,
        UOS.TotalQuestionsOwned AS OwnerTotalQuestions,
        UOS.GoldBadgesCount AS OwnerGoldBadges,
        Q.MaxCommentScore,
        Q.UniqueCommenters,
        Q.TotalBountyAmount,
        Q.DuplicateLinkCount,
        Q.LinkedPostCount,
        CDA.WasEverClosed,
        CDA.IsCurrentlyClosed,
        CDA.TotalSecondsClosed_Estimate,
        CDA.FirstClosedDate,
        CDA.LastReopenedDate,
        COALESCE(AA.Score, 0) AS AcceptedAnswerScore,
        AA_UOS.DisplayName AS AcceptedAnswerOwnerDisplayName,
        AA_UOS.Reputation AS AcceptedAnswerOwnerReputation,
        Q.ParsedTags,
        UOS.UserCreationDate,
        UOS.TotalPostScore,
        Q.RawTags,
        P_Q.LastEditDate,
        -- Aggregates specific to answers linked to the question
        COUNT(DISTINCT A.Id) AS TotalAnswersFound,
        AVG(A.Score) AS AverageAnswerScoreForQuestion,
        MAX(A.CreationDate) AS LatestAnswerDateForQuestion
    FROM
        Posts P_Q -- Alias for Posts table used as Question
    JOIN QuestionDetailedMetrics Q ON P_Q.Id = Q.QuestionId
    LEFT JOIN UserOverallStats UOS ON P_Q.OwnerUserId = UOS.UserId
    LEFT JOIN ClosedDurationAnalysis CDA ON Q.QuestionId = CDA.PostId
    LEFT JOIN Posts A ON A.ParentId = Q.QuestionId AND A.PostTypeId = 2 -- Answers to the question
    LEFT JOIN Posts AA ON Q.AcceptedAnswerId = AA.Id AND AA.PostTypeId = 2 -- The accepted answer
    LEFT JOIN UserOverallStats AA_UOS ON AA.OwnerUserId = AA_UOS.UserId
    WHERE
        P_Q.PostTypeId = 1
    GROUP BY -- Grouping for BaseQuestionData CTE to aggregate answer details
        Q.QuestionId, Q.QuestionTitle, Q.QuestionCreationDate, Q.QuestionScore, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount,
        UOS.UserId, UOS.DisplayName, UOS.Reputation, UOS.TotalQuestionsOwned, UOS.GoldBadgesCount, Q.MaxCommentScore, Q.UniqueCommenters,
        Q.TotalBountyAmount, Q.DuplicateLinkCount, Q.LinkedPostCount, CDA.WasEverClosed, CDA.IsCurrentlyClosed,
        CDA.TotalSecondsClosed_Estimate, CDA.FirstClosedDate, CDA.LastReopenedDate, AA.Score, AA_UOS.DisplayName, AA_UOS.Reputation,
        Q.ParsedTags, UOS.UserCreationDate, UOS.TotalPostScore, Q.RawTags, P_Q.LastEditDate
),
RankedQuestions AS (
    -- Applies window functions to the base question data.
    SELECT
        *,
        -- Ranks questions by score and view count within each owner's questions
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY QuestionScore DESC, ViewCount DESC) AS RankByOwnerScore,
        -- Divides questions into 10 groups based on creation date
        NTILE(10) OVER (ORDER BY QuestionCreationDate DESC) AS CreationDateDecile,
        -- Retrieves the score of the owner's previous question
        LAG(QuestionScore, 1, 0) OVER (PARTITION BY OwnerUserId ORDER BY QuestionCreationDate) AS PrevQuestionScoreByOwner
    FROM
        BaseQuestionData
)
-- Final selection of data with complex calculations, predicates, and string manipulations.
SELECT
    RQ.QuestionId,
    RQ.QuestionTitle,
    RQ.QuestionCreationDate,
    RQ.QuestionScore,
    RQ.ViewCount,
    RQ.AnswerCount,
    RQ.FavoriteCount,
    RQ.OwnerDisplayName,
    RQ.OwnerReputation,
    RQ.OwnerTotalQuestions,
    RQ.OwnerGoldBadges,
    RQ.MaxCommentScore,
    RQ.UniqueCommenters,
    RQ.TotalBountyAmount,
    RQ.DuplicateLinkCount,
    RQ.LinkedPostCount,
    COALESCE(RQ.WasEverClosed, FALSE) AS WasQuestionEverClosed,
    COALESCE(RQ.IsCurrentlyClosed, FALSE) AS IsQuestionCurrentlyClosed,
    RQ.TotalSecondsClosed_Estimate,
    RQ.FirstClosedDate,
    RQ.LastReopenedDate,
    RQ.AcceptedAnswerScore,
    RQ.AcceptedAnswerOwnerDisplayName,
    RQ.AcceptedAnswerOwnerReputation,
    -- Correlated subquery for counting unique upvoters
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = RQ.QuestionId AND V.VoteTypeId = 2) AS UniqueUpvotersCount,
    -- Correlated subquery for counting high-quality comments
    (SELECT COUNT(*) FROM Comments C WHERE C.PostId = RQ.QuestionId AND LENGTH(C.Text) > 100 AND C.Score >= 5) AS HighQualityCommentsCount,
    -- Complex CASE expression for categorizing questions
    CASE
        WHEN RQ.QuestionScore >= 50 AND RQ.ViewCount >= 1000 AND RQ.AnswerCount >= 5 THEN 'HotTopic'
        WHEN RQ.QuestionScore >= 10 AND RQ.AnswerCount >= 2 THEN 'Engaging'
        WHEN RQ.FavoriteCount > 0 AND RQ.QuestionScore > 0 THEN 'Interesting'
        ELSE 'Regular'
    END AS QuestionCategory,
    ARRAY_TO_STRING(RQ.ParsedTags, ',') AS FormattedTags,
    RQ.RankByOwnerScore,
    RQ.CreationDateDecile,
    RQ.PrevQuestionScoreByOwner,
    -- Calculation involving NULL logic and date functions
    RQ.TotalPostScore * 1.0 / NULLIF(EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, RQ.UserCreationDate)), 0) AS OwnerAvgDailyScore,
    -- Elaborate string expression using CONCAT_WS, CASE, REPLACE, SUBSTRING, and COALESCE for NULL handling
    CONCAT_WS(' | ',
        CASE WHEN RQ.QuestionTitle LIKE '%SQL%' THEN 'SQL_Related' ELSE NULL END,
        CASE WHEN RQ.QuestionTitle LIKE '%Python%' THEN 'Python_Related' ELSE NULL END,
        CASE WHEN RQ.RawTags ILIKE '%<performance>%' THEN 'PerformanceTag' ELSE NULL END,
        COALESCE(REPLACE(SUBSTRING(RQ.QuestionTitle, 1, 20), ' ', '_'), 'NoTitlePrefix')
    ) AS DerivedAttributesString
FROM
    RankedQuestions RQ
WHERE
    RQ.QuestionCreationDate >= '2020-01-01' -- Date range filter
    AND RQ.ViewCount >= 50
    AND (RQ.AnswerCount > 0 OR RQ.FavoriteCount > 0) -- NULL logic combined with OR
    AND (RQ.OwnerReputation > 5000 OR RQ.OwnerGoldBadges > 0)
    AND (RQ.RawTags LIKE '%<sql>%' OR RQ.RawTags LIKE '%<database>%') -- String pattern matching
    AND RQ.QuestionTitle IS NOT NULL AND LENGTH(TRIM(RQ.QuestionTitle)) > 10 -- NULL check and string length
    AND (RQ.AverageAnswerScoreForQuestion > 2 OR RQ.IsCurrentlyClosed IS FALSE) -- Complex predicate with NULL handling
ORDER BY
    RQ.OwnerReputation DESC, RQ.QuestionScore DESC, RQ.ViewCount DESC
LIMIT 1000;
