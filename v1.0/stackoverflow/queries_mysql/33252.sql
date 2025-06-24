
WITH RECURSIVE UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(COALESCE(C.VoteCount, 0)) AS TotalVotes,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN (
        SELECT 
            PostId, COUNT(*) AS VoteCount 
        FROM 
            Votes 
        GROUP BY 
            PostId
    ) C ON P.Id = C.PostId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
FilteredUsers AS (
    SELECT 
        UA.UserId,
        UA.DisplayName,
        UA.Reputation,
        UA.PostCount,
        UA.AnswerCount,
        UA.QuestionCount,
        UA.TotalVotes,
        UA.UserRank
    FROM 
        UserActivity UA
    WHERE 
        UA.Reputation > (SELECT AVG(Reputation) FROM Users)
)
SELECT 
    FU.DisplayName,
    FU.Reputation,
    FU.PostCount,
    FU.AnswerCount,
    FU.QuestionCount,
    FU.TotalVotes,
    FU.UserRank,
    (SELECT GROUP_CONCAT(T.TagName SEPARATOR ', ') 
     FROM Posts P 
     JOIN (
         SELECT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(P.Tags, ',', numbers.n), ',', -1)) AS TagName
         FROM 
         (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 
          UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) numbers
         WHERE CHAR_LENGTH(P.Tags) - CHAR_LENGTH(REPLACE(P.Tags, ',', '')) >= numbers.n - 1
     ) T ON T.TagName = P.Tags 
     WHERE P.OwnerUserId = FU.UserId) AS TagsUsed,
    (SELECT COUNT(*) 
     FROM Comments C 
     WHERE C.UserId = FU.UserId) AS CommentCount,
    (SELECT COUNT(*) 
     FROM Badges B 
     WHERE B.UserId = FU.UserId) AS BadgeCount
FROM 
    FilteredUsers FU
ORDER BY 
    FU.Reputation DESC
LIMIT 10;
