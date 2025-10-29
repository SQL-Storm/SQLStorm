-- {"query": "1915.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2748} 

WITH UserEngagement AS (
    -- Summarizes user activity and reputation quartiles
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        COUNT(DISTINCT C.Id) AS TotalCommentsByOwner,
        SUM(U.UpVotes) AS TotalUpvotesGivenByOwner,
        SUM(U.DownVotes) AS TotalDownvotesGivenByOwner,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgOwnerQuestionScore,
        MAX(U.LastAccessDate) AS LastUserAccessDate,
        -- Window function: Assigns users to deciles based on their reputation
        NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.LastAccessDate
    -- Filter for users with at least one post or comment to avoid mostly inactive users
    HAVING COUNT(DISTINCT P.Id) + COUNT(DISTINCT C.Id) > 0
),
QuestionDetailsAggregated AS (
    -- Aggregates various details for question posts, including string processing and correlated subqueries
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.Title,
        COALESCE(P.Tags, '') AS TagsString, -- Ensure TagsString is never NULL
        LENGTH(P.Body) AS BodyLength,
        P.LastEditDate,
        P.ClosedDate,
        -- Correlated subquery: Count of unique users who edited this question's title, body, or tags
        (
            SELECT COUNT(DISTINCT PH.UserId)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
            AND PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title/Body/Tags
        ) AS UniqueEditorCount,
        -- Correlated subquery: Retrieve the most recent close reason name if the post was closed
        (
            SELECT CRT.Name
            FROM PostHistory PH
            JOIN CloseReasonTypes CRT ON PH.Comment = CRT.Id::text -- Join PostHistory.Comment (varchar) with CloseReasonTypes.Id (smallint)
            WHERE PH.PostId = P.Id
            AND PH.PostHistoryTypeId = 10 -- Post Closed event
            ORDER BY PH.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReasonTypeName,
        -- String expression and NULL logic: Calculate the number of unique tags
        CASE
            WHEN P.Tags IS NULL OR P.Tags = '' THEN 0
            ELSE cardinality(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))
        END AS UniqueTagCount,
        -- Complicated predicate: Check if tags include 'sql' or 'database' (case-insensitive)
        CASE WHEN P.Tags ILIKE '%<sql>%' OR P.Tags ILIKE '%<database>%' THEN TRUE ELSE FALSE END AS RelatesToSqlOrDB,
        -- String expression: Extract the first tag from the Tags string, handling potential empty strings
        TRIM(BOTH '>' FROM SUBSTRING(COALESCE(P.Tags, '') FROM '(?<=<)[^>]+(?=>)')) AS FirstTag,
        P.AcceptedAnswerId
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Only process Questions
),
CommentActivitySummary AS (
    -- Summarizes comment activity per post
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LastCommentDateOnPost,
        -- String aggregation: Collect distinct display names of commenters, filtering out NULLs
        STRING_AGG(DISTINCT U.DisplayName, ', ') FILTER (WHERE U.DisplayName IS NOT NULL) AS DistinctCommenterNames
    FROM Comments C
    LEFT JOIN Users U ON C.UserId = U.Id
    GROUP BY C.PostId
),
PostLinkAnalysis AS (
    -- Analyzes linked and duplicate posts, includes string aggregation
    SELECT
        PL.PostId,
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN PL.RelatedPostId END) AS LinkedPostsCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicatePostsCount,
        -- String aggregation: Collect titles of duplicate posts, filtering out NULLs
        STRING_AGG(P_Related.Title, '; ') FILTER (WHERE P_Related.Title IS NOT NULL) AS DuplicatePostTitles
    FROM PostLinks PL
    LEFT JOIN Posts P_Related ON PL.RelatedPostId = P_Related.Id
    GROUP BY PL.PostId
),
UserBadgeStats AS (
    -- Aggregates badge statistics per user
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
AcceptedAnswerComparison AS (
    -- Compares the score of a question with its accepted answer, handling NULLs
    SELECT
        Q.QuestionId,
        Q.QuestionScore,
        A.Score AS AcceptedAnswerScore,
        Q.AcceptedAnswerId,
        -- NULL logic: If accepted answer score is NULL, treat it as 0 for difference calculation
        COALESCE(A.Score, 0) AS CoalescedAcceptedAnswerScore,
        Q.QuestionScore - COALESCE(A.Score, 0) AS ScoreDifference,
        CASE
            WHEN Q.QuestionScore > COALESCE(A.Score, 0) THEN 'Question Higher'
            WHEN Q.QuestionScore < COALESCE(A.Score, 0) THEN 'Answer Higher'
            ELSE 'Scores Equal'
        END AS ScoreComparisonText
    FROM QuestionDetailsAggregated Q
    JOIN Posts A ON Q.AcceptedAnswerId = A.Id
    WHERE Q.AcceptedAnswerId IS NOT NULL
),
-- Set operator (UNION ALL) to combine two criteria for "popular" questions
PopularQuestionsSet AS (
    SELECT QuestionId FROM QuestionDetailsAggregated WHERE ViewCount > 50000 AND FavoriteCount > 50
    UNION ALL
    SELECT QuestionId FROM QuestionDetailsAggregated WHERE QuestionScore > 100 AND AnswerCount > 5
)
SELECT
    QDA.QuestionId,
    QDA.QuestionCreationDate,
    QDA.Title,
    QDA.QuestionScore,
    QDA.ViewCount,
    QDA.AnswerCount,
    QDA.BodyLength,
    QDA.UniqueTagCount,
    QDA.RelatesToSqlOrDB,
    QDA.FirstTag,
    UE.DisplayName AS OwnerDisplayName,
    UE.Reputation AS OwnerReputation,
    UE.TotalPostsByOwner,
    UE.TotalCommentsByOwner,
    UBA.GoldBadges AS OwnerGoldBadges,
    UBA.SilverBadges AS OwnerSilverBadges,
    CAS.TotalCommentsOnPost,
    CAS.TotalCommentScore,
    CAS.DistinctCommenterNames,
    PLA.LinkedPostsCount,
    PLA.DuplicatePostsCount,
    PLA.DuplicatePostTitles,
    AAC.AcceptedAnswerScore,
    AAC.ScoreDifference,
    AAC.ScoreComparisonText,
    QDA.LastCloseReasonTypeName,
    -- Window function: Rank questions by score within each calendar year
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM QDA.QuestionCreationDate) ORDER BY QDA.QuestionScore DESC, QDA.ViewCount DESC) AS RankByYearlyScore,
    -- Window function: Calculate the average score of the owner's 5 preceding questions
    AVG(QDA.QuestionScore) OVER (
        PARTITION BY QDA.OwnerUserId
        ORDER BY QDA.QuestionCreationDate
        ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING
    ) AS AvgPrev5OwnerQuestionScore,
    -- Window function: Cumulative sum of view counts for questions by the same owner, ordered by creation date
    SUM(QDA.ViewCount) OVER (
        PARTITION BY QDA.OwnerUserId
        ORDER BY QDA.QuestionCreationDate
    ) AS CumulativeOwnerViewCount,
    -- Complicated calculation/expression with NULL logic: Score per answer, defaults to 0.0 if no answers
    COALESCE(QDA.QuestionScore * 1.0 / NULLIF(QDA.AnswerCount, 0), 0.0) AS ScorePerAnswerRatio,
    -- String expression: Categorize question based on keywords in title (case-insensitive)
    CASE
        WHEN QDA.Title ILIKE '%benchmark%' OR QDA.Title ILIKE '%performance%' THEN 'Performance Topic'
        WHEN QDA.Title ILIKE '%error%' OR QDA.Title ILIKE '%bug%' THEN 'Issue Topic'
        WHEN QDA.Title ILIKE '%tutorial%' OR QDA.Title ILIKE '%guide%' THEN 'Learning Resource'
        ELSE 'General Topic'
    END AS QuestionTopicCategory,
    -- Correlated subquery: Count how many answers the question owner provided to their own question
    (
        SELECT COUNT(P_Ans.Id)
        FROM Posts P_Ans
        WHERE P_Ans.ParentId = QDA.QuestionId
        AND P_Ans.OwnerUserId = QDA.OwnerUserId
        AND P_Ans.PostTypeId = 2 -- Is an answer
    ) AS OwnerSelfAnswerCount,
    -- Correlated subquery: Check if the owner has any Gold badges (Class = 1)
    (
        SELECT EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = QDA.OwnerUserId AND B.Class = 1)
    ) AS OwnerHasGoldBadge
FROM
    QuestionDetailsAggregated QDA
LEFT JOIN
    UserEngagement UE ON QDA.OwnerUserId = UE.UserId
LEFT JOIN
    CommentActivitySummary CAS ON QDA.QuestionId = CAS.PostId
LEFT JOIN
    PostLinkAnalysis PLA ON QDA.QuestionId = PLA.PostId
LEFT JOIN
    UserBadgeStats UBA ON QDA.OwnerUserId = UBA.UserId
LEFT JOIN
    AcceptedAnswerComparison AAC ON QDA.QuestionId = AAC.QuestionId
WHERE
    -- Filter using the result of a set operator CTE (PopularQuestionsSet)
    QDA.QuestionId IN (SELECT QuestionId FROM PopularQuestionsSet)
    AND QDA.QuestionScore >= 0
    AND QDA.QuestionCreationDate >= '2020-01-01' -- Only recent questions for more relevant data
    AND QDA.RelatesToSqlOrDB = TRUE -- Focus on questions related to SQL or databases
    -- NULL logic: Ensure the question has either been edited (UniqueEditorCount > 0) or has a recorded last edit date
    AND (QDA.UniqueEditorCount > 0 OR QDA.LastEditDate IS NOT NULL)
    AND UE.ReputationDecile <= 5 -- Consider questions from users in the top 5 reputation deciles
ORDER BY
    QDA.QuestionCreationDate DESC,
    RankByYearlyScore ASC
LIMIT 1000;
