-- {"query": "26014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 549} 

WITH 
  -- Calculate total reputation per user
  UserReputation AS (
    SELECT 
      U.Id, 
      U.Reputation + COALESCE(SUM(B.Class * 10), 0) AS TotalReputation
    FROM 
      Users U
    LEFT JOIN 
      Badges B ON U.Id = B.UserId
    GROUP BY 
      U.Id, U.Reputation
  ),
  
  -- Calculate total score per post
  PostScore AS (
    SELECT 
      P.Id, 
      P.Score + COALESCE(SUM(V.VoteTypeId = 2), 0) - COALESCE(SUM(V.VoteTypeId = 3), 0) AS TotalScore
    FROM 
      Posts P
    LEFT JOIN 
      Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    GROUP BY 
      P.Id, P.Score
  ),
  
  -- Calculate top 10 tags
  TopTags AS (
    SELECT 
      T.TagName, 
      COUNT(*) AS TagCount
    FROM 
      Posts P
    CROSS JOIN 
      LATERAL string_to_array(substring(P.Tags, 2, length(P.Tags)-2), ''><'') AS T(TagName)
    GROUP BY 
      T.TagName
    ORDER BY 
      TagCount DESC
    LIMIT 10
  )

SELECT 
  U.DisplayName, 
  UR.TotalReputation, 
  P.Title, 
  PS.TotalScore, 
  PH.Comment, 
  T.TagName
FROM 
  Users U
JOIN 
  UserReputation UR ON U.Id = UR.Id
JOIN 
  Posts P ON U.Id = P.OwnerUserId
JOIN 
  PostScore PS ON P.Id = PS.Id
JOIN 
  PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId = 10
JOIN 
  PostLinks PL ON P.Id = PL.PostId
JOIN 
  Posts P2 ON PL.RelatedPostId = P2.Id
JOIN 
  Votes V ON P2.Id = V.PostId AND V.VoteTypeId = 1
JOIN 
  LATERAL (
    SELECT 
      T.TagName
    FROM 
      TopTags T
    WHERE 
      T.TagName = ANY(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), ''><''))
  ) T ON TRUE
WHERE 
  P.PostTypeId = 1 AND P.Score > 10 AND UR.TotalReputation > 1000
ORDER BY 
  PS.TotalScore DESC, UR.TotalReputation DESC;
