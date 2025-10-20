-- {"query": "2041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 516} 

WITH RecentActiveUsers AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.CreationDate, 
        RANK() OVER (ORDER BY U.LastAccessDate DESC) AS AccessRank
    FROM Users U
    WHERE U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '7 days'
),
ActiveQuestionAuthors AS (
    SELECT
        Q.OwnerUserId,
        COUNT(DISTINCT Q.Id) AS QuestionCount,
        AVG(Q.ViewCount) AS AvgViewCount
    FROM Posts Q
    WHERE Q.PostTypeId = 1 -- Only questions
    GROUP BY Q.OwnerUserId
),
UserBadges AS (
    SELECT 
        B.UserId, 
        STRING_AGG(CASE B.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' ELSE 'Bronze' END, ', ') AS BadgeClasses
    FROM Badges B
    GROUP BY B.UserId
),
TopAnswerers AS (
    SELECT 
        A.OwnerUserId,
        COUNT(*) AS AnswerCount,
        SUM(CASE WHEN A.Score > 0 THEN 1 ELSE 0 END) AS UpvotedAnswers
    FROM Posts A
    WHERE A.PostTypeId = 2 -- Only answers
    GROUP BY A.OwnerUserId
),
PostCommentScores AS (
    SELECT
        C.PostId,
        AVG(C.Score) AS AvgCommentScore
    FROM Comments C
    GROUP BY C.PostId
)
SELECT 
    RU.DisplayName,
    RU.CreationDate,
    COALESCE(AQA.QuestionCount, 0) AS QuestionCount,
    COALESCE(AQA.AvgViewCount, 0) AS AvgViewCount,
    COALESCE(TA.AnswerCount, 0) AS AnswerCount,
    COALESCE(TA.UpvotedAnswers, 0) AS UpvotedAnswers,
    COALESCE(UF.BadgeClasses, 'None') AS BadgeClasses,
    COALESCE(PCS.AvgCommentScore, 0) AS AvgCommentScore
FROM RecentActiveUsers RU
LEFT JOIN ActiveQuestionAuthors AQA ON RU.UserId = AQA.OwnerUserId
LEFT JOIN TopAnswerers TA ON RU.UserId = TA.OwnerUserId
LEFT JOIN UserBadges UF ON RU.UserId = UF.UserId
LEFT JOIN PostCommentScores PCS ON RU.UserId = PCS.PostId
WHERE RU.AccessRank <= 50
ORDER BY RU.AccessRank;
