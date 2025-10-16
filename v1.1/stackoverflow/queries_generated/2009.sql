-- {"query": "2009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 552} 

WITH RecentUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COALESCE(SUM(V.BountyAmount), 0) AS TotalBountyEarned
    FROM 
        Users U
    LEFT JOIN 
        Votes V ON U.Id = V.UserId AND V.VoteTypeId = 9
    WHERE
        U.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
PopularQuestions AS (
    SELECT 
        P.Id AS QuestionId,
        P.Title,
        P.Score,
        COUNT(C.Id) AS CommentCount
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId 
    WHERE 
        P.PostTypeId = 1 
        AND P.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
    GROUP BY 
        P.Id, P.Title, P.Score
    ORDER BY 
        P.Score DESC
),
UserBadges AS (
    SELECT 
        U.Id AS UserId,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
)
SELECT 
    RU.UserId,
    RU.DisplayName,
    RU.Reputation,
    RU.TotalBountyEarned,
    COUNT(DISTINCT A.Id) AS AnswersCount,
    PB.GoldBadges,
    PB.SilverBadges,
    PB.BronzeBadges,
    COALESCE(PQ.CommentCount, 0) AS RecentPopularQuestionComments
FROM 
    RecentUsers RU
LEFT JOIN 
    Posts A ON RU.UserId = A.OwnerUserId AND A.PostTypeId = 2
LEFT JOIN 
    UserBadges PB ON RU.UserId = PB.UserId
LEFT JOIN 
    PopularQuestions PQ ON A.ParentId = PQ.QuestionId
GROUP BY 
    RU.UserId, RU.DisplayName, RU.Reputation, RU.TotalBountyEarned, 
    PB.GoldBadges, PB.SilverBadges, PB.BronzeBadges, PQ.CommentCount
HAVING 
    COUNT(DISTINCT A.Id) > 2
ORDER BY 
    RU.Reputation DESC, RU.TotalBountyEarned DESC;
