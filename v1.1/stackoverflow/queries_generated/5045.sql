-- {"query": "5045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1047} 
WITH RecentActiveUsers AS (
    SELECT U.Id AS UserId, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
           ROW_NUMBER() OVER (ORDER BY U.LastAccessDate DESC) AS rn
    FROM Users U
    WHERE U.Reputation > 0
      AND U.LastAccessDate >= (SELECT MAX(LastAccessDate) FROM Users) - INTERVAL '30 days'
),
TopScoredQuestions AS (
    SELECT P.Id AS QuestionId, P.Title, P.OwnerUserId, P.Score, P.ViewCount, P.CreationDate,
           COUNT(A.Id) AS AnswerCount,
           DENSE_RANK() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS dr
    FROM Posts P
    LEFT JOIN Posts A ON A.ParentId = P.Id AND A.PostTypeId = 2
    WHERE P.PostTypeId = 1
      AND P.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY P.Id, P.Title, P.OwnerUserId, P.Score, P.ViewCount, P.CreationDate
),
UserBadges AS (
    SELECT B.UserId,
           COUNT(*) FILTER (WHERE B.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE B.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
CommentSummary AS (
    SELECT C.PostId,
           COUNT(C.Id) AS CommentCount,
           MAX(C.Score) AS MaxCommentScore,
           STRING_AGG(LEFT(C.Text, 80), ' ||| ') AS SampleComments
    FROM Comments C
    WHERE C.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY C.PostId
),
QuestionClosure AS (
    SELECT PH.PostId,
           MIN(PH.CreationDate) AS FirstCloseDate,
           MAX(CRT.Name) AS CloseReason
    FROM PostHistory PH
    INNER JOIN CloseReasonTypes CRT
        ON CAST(PH.Comment AS INTEGER) = CRT.Id
    WHERE PH.PostHistoryTypeId = 10
    GROUP BY PH.PostId
)
SELECT
    Q.QuestionId,
    Q.Title,
    U.DisplayName AS Owner,
    U.Reputation,
    COALESCE(UB.GoldBadges, 0) AS GoldBadges,
    COALESCE(UB.SilverBadges, 0) AS SilverBadges,
    COALESCE(UB.BronzeBadges, 0) AS BronzeBadges,
    Q.Score,
    Q.ViewCount,
    Q.AnswerCount,
    EXTRACT(DAY FROM (CURRENT_DATE - Q.CreationDate)) AS DaysSinceAsked,
    CASE
        WHEN Q.AnswerCount = 0 THEN 'Unanswered'
        WHEN Q.AnswerCount BETWEEN 1 AND 2 THEN 'Low engagement'
        WHEN Q.AnswerCount BETWEEN 3 AND 10 THEN 'Active'
        ELSE 'Very Hot'
    END AS EngagementLevel,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    CS.SampleComments,
    QC.FirstCloseDate,
    QC.CloseReason,
    CASE WHEN QC.FirstCloseDate IS NULL THEN 'Open' ELSE 'Closed' END AS Status,
    ( SELECT COUNT(*) FROM Votes V WHERE V.PostId = Q.QuestionId AND V.VoteTypeId = 2 ) AS Upvotes,
    ( SELECT COUNT(*) FROM Votes V WHERE V.PostId = Q.QuestionId AND V.VoteTypeId = 3 ) AS Downvotes,
    CASE
        WHEN ( SELECT COUNT(*) FROM Votes V WHERE V.PostId = Q.QuestionId AND V.VoteTypeId = 2 ) >
             ( SELECT COUNT(*) FROM Votes V WHERE V.PostId = Q.QuestionId AND V.VoteTypeId = 3 ) THEN 'Well-Received'
        ELSE 'Controversial/Negative'
    END AS CommunityReception,
    ( SELECT string_agg(tag, ', ')
        FROM unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) tag
        WHERE P.Id = Q.QuestionId
    ) AS Tags
FROM TopScoredQuestions Q
LEFT JOIN Users U ON U.Id = Q.OwnerUserId
LEFT JOIN UserBadges UB ON UB.UserId = U.Id
LEFT JOIN CommentSummary CS ON CS.PostId = Q.QuestionId
LEFT JOIN QuestionClosure QC ON QC.PostId = Q.QuestionId
LEFT JOIN Posts P ON P.Id = Q.QuestionId
WHERE Q.dr <= 50
  AND (
     U.Id IN (SELECT UserId FROM RecentActiveUsers WHERE rn <= 100)
     OR Q.Score >= 10
     OR Q.AnswerCount >= 5
  )
ORDER BY Q.Score DESC, Q.ViewCount DESC
LIMIT 50;