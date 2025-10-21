-- {"query": "13018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 648} 

WITH TopUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(DISTINCT P.Id) AS TotalPosts,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS Rank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 1 AND P.ClosedDate IS NULL
    GROUP BY U.Id
    HAVING COUNT(DISTINCT P.Id) > 5
),
EditedPosts AS (
    SELECT 
        P.Id AS PostId, 
        P.OwnerUserId,
        MAX(PH.CreationDate) AS LastEditDate
    FROM Posts P
    JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) AND P.PostTypeId = 1
    GROUP BY P.Id
),
UserPerformance AS (
    SELECT 
        TU.Id,
        TU.DisplayName,
        TU.Reputation,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 2 THEN 1 ELSE 0 END), 0) AS InitialPosts,
        COALESCE(SUM(CASE WHEN EP.LastEditDate > P.CreationDate THEN 1 ELSE 0 END), 0) AS EditedPosts,
        AVG(CASE WHEN P.Score > 10 THEN P.Score ELSE NULL END) AS AvgHighScore,
        STRING_AGG(DISTINCT T.TagName, ', ') AS PopularTags
    FROM TopUsers TU
    LEFT JOIN Posts P ON TU.Id = P.OwnerUserId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN EditedPosts EP ON P.Id = EP.PostId
    LEFT JOIN LATERAL (
        SELECT 
            TRIM(BOTH '<>' FROM UNNEST(string_to_array(substring(Tags, 2, length(Tags) - 2), ''><''))) AS TagName
        FROM Posts 
        WHERE OwnerUserId = TU.Id AND PostTypeId = 1
    ) T ON TRUE
    WHERE PH.PostHistoryTypeId = 2 OR EP.LastEditDate IS NOT NULL
    GROUP BY TU.Id
)
SELECT 
    UP.DisplayName,
    UP.Reputation,
    UP.TotalPosts,
    COALESCE(UP.InitialPosts, 0) AS InitialPosts,
    COALESCE(UP.EditedPosts, 0) AS EditedPosts,
    ROUND(COALESCE(UP.AvgHighScore, 0), 2) AS AvgHighScore,
    UP.PopularTags
FROM UserPerformance UP
WHERE UP.Rank <= 10
ORDER BY UP.Reputation DESC;
