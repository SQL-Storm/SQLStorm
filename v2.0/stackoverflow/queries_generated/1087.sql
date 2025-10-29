-- {"query": "1087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2752} 

WITH UserEngagementSummary AS (
    -- This CTE identifies high-performing users based on reputation, answer count, score, and Gold badges,
    -- combining two different criteria sets using UNION ALL to stress set operator performance.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT A.Id) AS TotalAnswers,
        COALESCE(SUM(A.Score), 0) AS TotalAnswerScore,
        COALESCE(AVG(A.Score), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT AcceptedQ.Id) AS AcceptedAnswersProvidedCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        MIN(CASE WHEN B.Class = 1 THEN B.Date END) AS FirstGoldBadgeDate,
        'HighReputation' AS UserCategory
    FROM
        Users U
    LEFT JOIN
        Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2 -- Only consider answers
    LEFT JOIN
        Posts AcceptedQ ON A.Id = AcceptedQ.AcceptedAnswerId AND AcceptedQ.PostTypeId = 1 -- Questions where A is the accepted answer
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING
        U.Reputation >= 10000 -- High reputation threshold
        AND COUNT(DISTINCT A.Id) >= 50 -- At least 50 answers
        AND SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) >= 1 -- At least one Gold badge
        AND U.LastAccessDate IS NOT NULL -- Example of NULL logic in HAVING

    UNION ALL

    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT A.Id) AS TotalAnswers,
        COALESCE(SUM(A.Score), 0) AS TotalAnswerScore,
        COALESCE(AVG(A.Score), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT AcceptedQ.Id) AS AcceptedAnswersProvidedCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        MIN(CASE WHEN B.Class = 1 THEN B.Date END) AS FirstGoldBadgeDate,
        'HighScoreContributor' AS UserCategory
    FROM
        Users U
    INNER JOIN
        Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2 -- Must have answers for this group
    LEFT JOIN
        Posts AcceptedQ ON A.Id = AcceptedQ.AcceptedAnswerId AND AcceptedQ.PostTypeId = 1
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING
        COALESCE(SUM(A.Score), 0) >= 2000 -- Very high total answer score
        AND COUNT(DISTINCT A.Id) >= 10 -- At least 10 answers
        AND U.Reputation < 10000 -- Exclude those already in the 'HighReputation' group for distinct sets
        AND U.LastAccessDate IS NOT NULL
),
QuestionAnswerDetails AS (
    -- This CTE prepares detailed metrics for questions and their accepted answers,
    -- incorporating multiple correlated subqueries and string manipulations.
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Tags,
        A.Id AS AcceptedAnswerId,
        A.OwnerUserId AS AcceptedAnswerOwnerId,
        A.Score AS AcceptedAnswerScore,
        COALESCE(Q.AnswerCount, 0) AS TotalAnswerCountForQuestion,
        Q.ViewCount AS QuestionViewCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = Q.Id AND C.CreationDate > Q.CreationDate) AS QuestionCommentCount, -- Correlated Subquery 1: comments after question creation
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS QuestionEditCount, -- Correlated Subquery 2: count of title/body/tag edits
        Q.ClosedDate IS NOT NULL AS IsQuestionClosed, -- Boolean for NULL logic
        Q.LastActivityDate AS QuestionLastActivityDate,
        -- Complex string expression and NULL logic for a calculated field
        COALESCE(SUBSTRING(Q.Body, 1, 100), 'No Body Excerpt') AS BodyExcerpt,
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId = 2) AS LatestUpvoteDate -- Correlated Subquery 3: Latest upvote on question
    FROM
        Posts Q
    INNER JOIN
        Posts A ON Q.AcceptedAnswerId = A.Id AND Q.PostTypeId = 1 AND A.PostTypeId = 2 -- Join only questions with accepted answers
    WHERE
        Q.CreationDate >= '2020-01-01' -- Filter for recent questions
        AND Q.Tags IS NOT NULL -- Ensure tags exist for string operations
        AND Q.Score > 0 -- Only questions with positive scores
),
AggregatedTagMetrics AS (
    -- This CTE expands on the question/answer details by unnesting tags and applying window functions for tag-specific analysis.
    SELECT
        QAD.QuestionId,
        QAD.QuestionTitle,
        QAD.QuestionCreationDate,
        QAD.QuestionOwnerId,
        QAD.AcceptedAnswerId,
        QAD.AcceptedAnswerOwnerId,
        QAD.AcceptedAnswerScore,
        QAD.TotalAnswerCountForQuestion,
        QAD.QuestionFavoriteCount,
        QAD.QuestionCommentCount,
        QAD.QuestionEditCount,
        QAD.IsQuestionClosed,
        QAD.QuestionLastActivityDate,
        QAD.BodyExcerpt,
        QAD.LatestUpvoteDate,
        TRIM(tag_value) AS TagName, -- String expression with TRIM
        ROW_NUMBER() OVER (PARTITION BY QAD.AcceptedAnswerOwnerId ORDER BY QAD.QuestionCreationDate DESC, QAD.QuestionId) AS AnswererQuestionRankByDate, -- Window function: rank questions by date per answerer
        AVG(QAD.AcceptedAnswerScore) OVER (PARTITION BY TRIM(tag_value)) AS AvgAcceptedScorePerTag, -- Window function: average score per tag
        COUNT(QAD.QuestionId) OVER (PARTITION BY TRIM(tag_value)) AS QuestionCountPerTag, -- Window function: count questions per tag
        NTH_VALUE(QAD.QuestionTitle, 1) OVER (PARTITION BY TRIM(tag_value) ORDER BY QAD.QuestionViewCount DESC) AS MostViewedQuestionInTag -- Window function: most viewed question title per tag
    FROM
        QuestionAnswerDetails QAD
    CROSS JOIN LATERAL
        UNNEST(string_to_array(SUBSTRING(QAD.Tags, 2, LENGTH(QAD.Tags)-2), '><')) AS tag_value -- Exploding tags array (PostgreSQL specific)
    WHERE
        LENGTH(TRIM(tag_value)) > 0 -- Filter out empty tags
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.UserCategory,
    UES.TotalAnswers,
    UES.AvgAnswerScore,
    UES.AcceptedAnswersProvidedCount,
    UES.GoldBadgesCount,
    UES.FirstGoldBadgeDate,
    ATM.QuestionId,
    ATM.QuestionTitle,
    ATM.TagName,
    ATM.AcceptedAnswerScore,
    ATM.AvgAcceptedScorePerTag,
    ATM.QuestionCountPerTag,
    ATM.AnswererQuestionRankByDate,
    ATM.QuestionCommentCount,
    ATM.QuestionEditCount,
    ATM.IsQuestionClosed,
    ATM.MostViewedQuestionInTag,
    -- Complicated predicate/expression/calculation using CASE and date arithmetic
    CASE
        WHEN UES.UserLastAccessDate > ATM.QuestionLastActivityDate THEN 'UserActivityMoreRecent'
        WHEN UES.UserLastAccessDate < ATM.QuestionLastActivityDate THEN 'QuestionActivityMoreRecent'
        ELSE 'ActivityDatesMatch'
    END AS ActivityComparison,
    -- Correlated Subquery 4: count of posts upvoted by the answerer within the same tag, after question creation.
    (SELECT COUNT(DISTINCT V.PostId)
     FROM Votes V
     WHERE V.UserId = UES.UserId
       AND V.VoteTypeId = 2 -- UpMod (upvote)
       AND V.CreationDate >= ATM.QuestionCreationDate
       AND EXISTS (
           SELECT 1
           FROM Posts UpvotedPost
           CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(UpvotedPost.Tags, 2, LENGTH(UpvotedPost.Tags)-2), '><')) AS upvote_tag
           WHERE UpvotedPost.Id = V.PostId
             AND TRIM(upvote_tag) = ATM.TagName
             AND UpvotedPost.PostTypeId = 1 -- Only consider upvoted questions
       )
    ) AS UpvotedQuestionsInSameTagByAnswerer,
    -- Correlated Subquery 5: retrieve the name of the latest post history type for the question, with NULL handling.
    COALESCE(
        (SELECT PHT.Name FROM PostHistory PHS
         INNER JOIN PostHistoryTypes PHT ON PHS.PostHistoryTypeId = PHT.Id
         WHERE PHS.PostId = ATM.QuestionId
         ORDER BY PHS.CreationDate DESC
         LIMIT 1),
        'NoDetailedHistory'
    ) AS LatestQuestionHistoryTypeName,
    -- Check if the question received an upvote before the accepted answer was provided
    ATM.LatestUpvoteDate < ATM.QuestionCreationDate + INTERVAL '1 day' AND ATM.LatestUpvoteDate IS NOT NULL AS UpvoteWithinDayOfQuestion,
    COALESCE(Users.Location, 'Unknown Location') AS UserLocation -- Using COALESCE for NULL logic on a joined field
FROM
    UserEngagementSummary UES
INNER JOIN
    AggregatedTagMetrics ATM ON UES.UserId = ATM.AcceptedAnswerOwnerId
LEFT JOIN Users ON UES.UserId = Users.Id -- Join back to Users table for more user details
WHERE
    ATM.AnswererQuestionRankByDate <= 5 -- Limit to the top 5 most recent accepted answers by date for this user
    AND ATM.TagName IN ('sql', 'database', 'performance', 'indexing', 'json', 'python', 'javascript') -- Focus on a selection of tags
    AND ATM.AcceptedAnswerScore > ATM.AvgAcceptedScorePerTag -- Ensure the answer's score is better than the average for its tag
    AND UES.UserCreationDate < ATM.QuestionCreationDate -- User must have existed before the question was created
    AND (ATM.IsQuestionClosed = FALSE OR UES.Reputation > 25000) -- Complex boolean/NULL logic: open questions or closed questions only if the user is very high rep
    AND (LENGTH(TRIM(ATM.BodyExcerpt)) > 50 OR ATM.QuestionFavoriteCount > 10) -- Another complex predicate using string length and numeric comparison
ORDER BY
    UES.Reputation DESC,
    UES.UserId,
    ATM.TagName,
    ATM.AnswererQuestionRankByDate ASC;
