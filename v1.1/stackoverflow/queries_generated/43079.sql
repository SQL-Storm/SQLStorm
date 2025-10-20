-- {"query": "43079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 651} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(U.LastAccessDate) AS LastAccessDate
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
RecentQuestions AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.OwnerUserId,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.Tags,
        STRING_AGG(DISTINCT T.TagName, ', ') AS TagNames
    FROM 
        Posts P
    CROSS JOIN LATERAL 
        UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS TagParts(Tag)
    JOIN 
        Tags T ON T.TagName = TagParts.Tag
    WHERE 
        P.PostTypeId = 1 AND
        P.CreationDate >= NOW() - INTERVAL '3 months'
    GROUP BY 
        P.Id, P.Title, P.CreationDate, P.OwnerUserId, P.ViewCount, P.AnswerCount, P.CommentCount, P.Tags
    HAVING 
        COUNT(DISTINCT T.Id) > 2
)
SELECT 
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.TotalPosts,
    UA.HighScorePosts,
    UA.TotalBadges,
    UA.GoldBadges,
    UA.LastAccessDate,
    RQ.PostId,
    RQ.Title,
    RQ.CreationDate,
    RQ.ViewCount,
    RQ.AnswerCount,
    RQ.CommentCount,
    RQ.TagNames
FROM 
    UserActivity UA
JOIN 
    RecentQuestions RQ ON UA.UserId = RQ.OwnerUserId
WHERE 
    UA.TotalPosts > 10 AND 
    UA.GoldBadges > 0
ORDER BY 
    UA.Reputation DESC, RQ.ViewCount DESC
LIMIT 100;
