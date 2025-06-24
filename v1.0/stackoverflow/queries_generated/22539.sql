WITH UserReputationCTE AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(A.Id) AS AcceptedAnswers,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(P.ViewCount) AS TotalViewCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts A ON A.AcceptedAnswerId = P.Id AND P.PostTypeId = 1
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY U.Id
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        AcceptedAnswers,
        CommentCount,
        TotalViewCount,
        ROW_NUMBER() OVER (PARTITION BY CASE WHEN Reputation IS NULL THEN 0 ELSE 1 END 
                           ORDER BY Reputation DESC, AcceptedAnswers DESC) AS Rank
    FROM UserReputationCTE
),
PopularTags AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalViews
    FROM Tags T
    JOIN Posts P ON POSITION(CONCAT('>', T.TagName, '<') IN '<' || P.Tags || '>') > 0
    GROUP BY T.TagName
    HAVING SUM(P.ViewCount) IS NOT NULL AND COUNT(P.Id) > 10
)
SELECT 
    U.DisplayName,
    U.Reputation,
    U.AcceptedAnswers,
    U.CommentCount,
    U.TotalViewCount,
    CASE 
        WHEN U.Rank <= 10 THEN 'Top User'
        ELSE 'Regular User'
    END AS UserCategory,
    T.TagName,
    T.PostCount,
    T.TotalViews,
    STRING_AGG(DISTINCT PH.Comment, '; ') AS HistoryComments
FROM TopUsers U
LEFT JOIN PostHistory PH ON U.UserId = PH.UserId
LEFT JOIN PopularTags T ON U.CommentCount >= 5
WHERE U.Reputation IS NOT NULL
GROUP BY U.DisplayName, U.Reputation, U.AcceptedAnswers,
         U.CommentCount, U.TotalViewCount, U.Rank, T.TagName, T.PostCount, T.TotalViews
ORDER BY U.Reputation DESC, T.TotalViews DESC
LIMIT 25;

-- Additional complexity: handling NULL in ranking and evaluating performance
SELECT 
    U.UserId,
    COALESCE(U.DisplayName, 'Anonymous') AS DisplayName,
    COUNT(DISTINCT V.Id) AS TotalVotes,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(P.ViewCount) AS AggregateViews
FROM Users U
LEFT JOIN Votes V ON U.Id = V.UserId
LEFT JOIN Posts P ON P.OwnerUserId = U.Id
WHERE U.Reputation IS NOT NULL
AND (U.Location IS NOT NULL OR U.EmailHash IS NOT NULL)
GROUP BY U.UserId, U.DisplayName
HAVING COUNT(P.Id) > 5 OR SUM(P.ViewCount) > 1000
ORDER BY AggregateViews DESC, TotalVotes DESC;

