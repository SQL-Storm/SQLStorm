-- {"query": "58037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 2107} 

WITH ActiveUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation, 
        U.CreationDate,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        MAX(B.Class) AS HighestBadgeClass,
        STRING_AGG(DISTINCT T.TagName, '; ') AS TopTags
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Badges B ON U.Id = B.UserId AND B.Date > CURRENT_DATE - INTERVAL '2 years'
    LEFT JOIN LATERAL (
        SELECT unnest(STRING_TO_ARRAY(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS Tag
    ) PTags ON P.PostTypeId = 1
    LEFT JOIN Tags T ON PTags.Tag = T.TagName
    WHERE 
        U.Reputation > 5000
        AND P.CreationDate BETWEEN '2015-01-01' AND '2023-12-31'
        AND (P.Score > 50 OR P.ViewCount > 10000)
    GROUP BY U.Id
    HAVING COUNT(DISTINCT P.Id) > 20 AND COUNT(DISTINCT V.Id) > 100
)
SELECT 
    AU.*,
    (SELECT AVG(AnswerCount) FROM Posts WHERE OwnerUserId = AU.Id AND PostTypeId = 1) AS AvgAnswersPerQuestion,
    RANK() OVER (ORDER BY (QuestionsAsked * 3 + AnswersProvided * 2 + TotalComments) DESC) AS EngagementRank,
    (SELECT COUNT(*) FROM PostHistory PH 
     WHERE PH.UserId = AU.Id AND PH.PostHistoryTypeId IN (2,5,8) 
     AND PH.CreationDate > CURRENT_DATE - INTERVAL '1 year') AS RecentEdits,
    (SELECT json_agg(json_build_object('RelatedPostId', PL.RelatedPostId, 'LinkType', LT.Name))
     FROM PostLinks PL 
     JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
     WHERE PL.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = AU.Id)) AS PostRelations
FROM ActiveUsers AU
WHERE HighestBadgeClass IS NOT NULL OR DownvotesReceived < UpvotesReceived * 0.1
ORDER BY EngagementRank, Reputation DESC
LIMIT 250;
