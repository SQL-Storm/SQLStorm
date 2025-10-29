-- {"query": "1222.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3258} 

WITH EnrichedUsers AS (
    -- CTE 1: Gathers detailed information and activity for active users, including their average post scores and badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        -- Calculate average score only for questions and answers owned by the user
        COALESCE(AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END), 0) AS AvgQAScoreOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(B.Date) FILTER (WHERE B.Class = 1) AS LatestGoldBadgeDate, -- PostgreSQL specific FILTER clause
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgeCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation >= 10000 -- Focus on higher reputation users
      AND U.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year' -- Recently active users
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 50 OR COUNT(DISTINCT C.Id) > 100
),
QuestionEngagementMetrics AS (
    -- CTE 2: Aggregates engagement statistics for questions, including comment and vote counts, and calculates a normalized engagement factor
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.LastActivityDate,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteTypeCount, -- VoteType 5 is for "Favorite"
        MAX(C.CreationDate) AS LatestCommentDate,
        (CAST(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NUMERIC) * 2 + COUNT(DISTINCT C.Id) * 1.5 + Q.FavoriteCount * 3 + Q.ViewCount * 0.01)
        / NULLIF(CAST(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NUMERIC) + 1, 0) AS CalculatedEngagementFactor
    FROM Posts Q
    LEFT JOIN Comments C ON Q.Id = C.PostId
    LEFT JOIN Votes V ON Q.Id = V.PostId
    WHERE Q.PostTypeId = 1 -- Only questions
      AND Q.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.LastActivityDate
    HAVING (COUNT(DISTINCT C.Id) > 5 AND SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) > 10)
        OR Q.ViewCount > 5000
),
PostContentEvolution AS (
    -- CTE 3: Summarizes the editing activity for posts, focusing on content changes
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 7) THEN 1 ELSE 0 END) AS TitleEditRollbackCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS BodyEditRollbackCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (6, 9) THEN 1 ELSE 0 END) AS TagsEditRollbackCount,
        MAX(PH.CreationDate) AS LastContentEditDate,
        MIN(PH.CreationDate) AS FirstContentEditDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Only content modification and rollback history types
    GROUP BY PH.PostId
    HAVING COUNT(PH.Id) >= 2 -- At least two edits/rollbacks for content
),
RelatedPostsSummary AS (
    -- CTE 4: Identifies posts that are either duplicates or linked to other high-score posts, using a set operator
    SELECT
        P.Id AS PostId,
        STRING_AGG(DISTINCT PL.RelatedPostId::TEXT, ',') AS LinkedRelatedPosts,
        MAX(P.Score) AS MaxRelatedPostScore,
        'LinkedOrDuplicate' AS RelationType
    FROM Posts P
    INNER JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE PL.LinkTypeId IN (1, 3) -- 1 = Linked, 3 = Duplicate
      AND P.Score > 10
    GROUP BY P.Id
    UNION ALL
    SELECT
        P.Id AS PostId,
        'SelfReferenced' AS LinkedRelatedPosts,
        P.Score AS MaxRelatedPostScore,
        'SelfReferenced' AS RelationType
    FROM Posts P
    WHERE P.Body LIKE '%stackoverflow.com/questions/%'
      AND P.PostTypeId = 1
      AND P.Score > 20
)
SELECT
    QEM.QuestionId,
    Q.Title,
    Q.Body AS QuestionBodySample, -- Access a large text column for I/O and string operations
    Q.Tags,
    QEM.QuestionCreationDate,
    Q.LastActivityDate,
    EU.DisplayName AS QuestionOwnerDisplayName,
    EU.Reputation AS QuestionOwnerReputation,
    EU.AvgQAScoreOwned AS OwnerAvgPostScore,
    QEM.QuestionScore,
    QEM.ViewCount,
    QEM.AnswerCount,
    QEM.TotalComments,
    QEM.UpVoteCount,
    QEM.DownVoteCount,
    QEM.FavoriteVoteTypeCount AS ExplicitFavoriteVotes,
    Q.FavoriteCount AS PostTableFavoriteCount, -- The denormalized favorite count in Posts table
    PCE.TotalHistoryEntries AS ContentHistoryEntries,
    PCE.TitleEditRollbackCount,
    PCE.BodyEditRollbackCount,
    PCE.TagsEditRollbackCount,
    PCE.LastContentEditDate,
    COALESCE(A.Id, -1) AS AcceptedAnswerId,
    COALESCE(A.Score, 0) AS AcceptedAnswerScore,
    COALESCE(AU.DisplayName, A.OwnerDisplayName, 'N/A') AS AcceptedAnswerOwnerDisplayName,
    COALESCE(AU.Reputation, 0) AS AcceptedAnswerOwnerReputation,
    -- Correlated Subquery 1: Determines if the accepted answer was provided by a 'super-expert' relative to the question owner
    CASE WHEN Q.AcceptedAnswerId IS NOT NULL THEN
        (SELECT CASE WHEN AU_Inner.Reputation > EU.Reputation * 1.5 THEN 'Super-Expert Answer' ELSE 'Standard Answer' END
         FROM Users AU_Inner WHERE AU_Inner.Id = A.OwnerUserId)
    ELSE 'No Accepted Answer' END AS AcceptedAnswerExpertiseLevel,
    -- Correlated Subquery 2: Fetches the 'latest significant comment' from the question owner, if available
    (SELECT COALESCE(C_Owner.Text, 'No recent owner comment')
     FROM Comments C_Owner
     WHERE C_Owner.PostId = Q.Id AND C_Owner.UserId = Q.OwnerUserId
       AND C_Owner.CreationDate = (SELECT MAX(CX.CreationDate) FROM Comments CX WHERE CX.PostId = Q.Id AND CX.UserId = Q.OwnerUserId AND LENGTH(CX.Text) > 50)
    ) AS OwnerLastSignificantComment,
    RPS.LinkedRelatedPosts,
    RPS.RelationType AS PostLinkRelationType,
    -- Window Function 1: Ranks questions by their calculated engagement factor within their primary tag group
    RANK() OVER (PARTITION BY SUBSTRING(Q.Tags FROM 2 FOR POSITION('>' IN Q.Tags)-2) ORDER BY QEM.CalculatedEngagementFactor DESC, QEM.QuestionScore DESC) AS RankByEngagementInPrimaryTag,
    -- Window Function 2: Calculates the average score of the last 3 questions posted by the owner
    AVG(QEM.QuestionScore) OVER (PARTITION BY EU.UserId ORDER BY QEM.QuestionCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS OwnerTrailingAvgQuestionScore,
    -- Window Function 3: Difference in days between the current question's creation and the owner's first gold badge date
    EXTRACT(DAY FROM (QEM.QuestionCreationDate - EU.LatestGoldBadgeDate)) AS DaysSinceOwnerGoldBadgeBeforePost,
    QEM.CalculatedEngagementFactor,
    -- Complex String Expression: Extracts the first tag and checks for a specific pattern
    TRIM(SUBSTRING(Q.Tags FROM 2 FOR POSITION('>' IN Q.Tags)-2)) AS PrimaryTagCleaned,
    CASE
        WHEN Q.Body LIKE '%benchmark%' AND Q.Body LIKE '%query%' THEN 'Benchmark-Oriented'
        WHEN Q.Title LIKE '%performance%' OR Q.Title LIKE '%slow%' THEN 'Performance-Issue-Oriented'
        ELSE 'General Technical'
    END AS ContentTopicCategory,
    -- NULL Logic: Using COALESCE for display and IS NULL in a logical expression
    COALESCE(CLT.Name, 'No explicit close reason') AS CloseReasonTypeName,
    CASE
        WHEN Q.ClosedDate IS NOT NULL AND Q.AcceptedAnswerId IS NULL THEN 'Closed Without Accepted Answer'
        WHEN Q.ClosedDate IS NULL AND Q.AnswerCount = 0 AND QEM.TotalComments > 5 THEN 'Unanswered But Debated'
        WHEN EU.GoldBadgeCount > 0 AND EU.GoldBadgeCount < 3 THEN 'Owner Developing'
        ELSE 'Standard Status'
    END AS QuestionDetailedStatus,
    LENGTH(Q.Body) AS QuestionBodyLengthCharacters,
    NULLIF(Q.AnswerCount, 0) AS NonZeroAnswerCount
FROM Posts Q
INNER JOIN QuestionEngagementMetrics QEM ON Q.Id = QEM.QuestionId
LEFT JOIN EnrichedUsers EU ON Q.OwnerUserId = EU.UserId
LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2 -- Accepted Answer
LEFT JOIN Users AU ON A.OwnerUserId = AU.Id -- Accepted Answer Owner
LEFT JOIN PostContentEvolution PCE ON Q.Id = PCE.PostId
LEFT JOIN RelatedPostsSummary RPS ON Q.Id = RPS.PostId
LEFT JOIN PostHistory PHC ON Q.Id = PHC.PostId AND PHC.PostHistoryTypeId = 10 AND PHC.CreationDate = (SELECT MAX(PHX.CreationDate) FROM PostHistory PHX WHERE PHX.PostId = Q.Id AND PHX.PostHistoryTypeId = 10) -- Get the latest close history entry
LEFT JOIN CloseReasonTypes CLT ON PHC.Comment IS NOT NULL AND CLT.Id = CAST(PHC.Comment AS SMALLINT) -- Join to get the close reason name
WHERE
    Q.PostTypeId = 1 -- Ensure it's a question
    AND EU.UserId IS NOT NULL -- Only consider questions from enriched, active users
    AND QEM.CalculatedEngagementFactor > 100 -- Filter for highly engaged questions
    AND (
        (PCE.BodyEditRollbackCount >= 3 AND PCE.TagsEditRollbackCount >= 1) -- Questions with significant content & tag evolution
        OR (Q.FavoriteCount >= 15 AND QEM.UpVoteCount > QEM.DownVoteCount * 3) -- Or highly favorited with strong positive sentiment
    )
    -- Complex predicate involving dates, string search, and NULL logic
    AND (
        (QEM.QuestionCreationDate BETWEEN EU.UserCreationDate AND EU.UserCreationDate + INTERVAL '3 year') -- Question posted within 3 years of user's creation
        AND (Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<database>%' OR Q.Tags LIKE '%<optimization>%') -- Related to specific tech topics
        AND (Q.ClosedDate IS NULL OR (Q.ClosedDate IS NOT NULL AND QEM.LatestCommentDate > Q.ClosedDate - INTERVAL '6 months')) -- Not closed, or activity continued after closing
    )
    -- EXISTS clause: Ensure there's at least one related post that is either a duplicate or heavily linked
    AND EXISTS (
        SELECT 1
        FROM RelatedPostsSummary RPS_Inner
        WHERE RPS_Inner.PostId = Q.Id AND RPS_Inner.MaxRelatedPostScore > QEM.QuestionScore / 2
    )
    -- NOT EXISTS clause: Exclude questions that have been deleted
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_Deleted
        WHERE PH_Deleted.PostId = Q.Id AND PH_Deleted.PostHistoryTypeId = 12 -- Post deleted
    )
ORDER BY
    QEM.CalculatedEngagementFactor DESC,
    OwnerTrailingAvgQuestionScore DESC,
    QuestionCreationDate DESC,
    Q.ViewCount DESC
LIMIT 5000;
