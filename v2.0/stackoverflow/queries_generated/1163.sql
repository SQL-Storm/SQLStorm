-- {"query": "1163.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2808} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity, reputation, badges, and categorizes them into reputation quartiles.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity,
        NTILE(4) OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS ReputationQuartile, -- Window function: NTILE to categorize users
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    WHERE U.Reputation > 500
      AND U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' -- Filter for active users
      AND U.AboutMe IS NOT NULL -- NULL logic: user must have an 'About Me' section
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
QuestionMetricsBase AS (
    -- CTE 2: Gathers core question data, calculates answer statistics and controversy score.
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.OwnerUserId,
        Q.Tags,
        COALESCE(Q.FavoriteCount, 0) AS FavoriteCount, -- NULL logic: Default FavoriteCount to 0 if NULL
        -- Correlated Subquery: Calculate average score of its answers
        (SELECT AVG(A.Score) FROM Posts AS A WHERE A.ParentId = Q.Id AND A.PostTypeId = 2) AS AverageAnswerScore,
        -- Correlated Subquery: Get the most recent PostHistoryType for the question
        (SELECT PH.PostHistoryTypeId FROM PostHistory AS PH WHERE PH.PostId = Q.Id ORDER BY PH.CreationDate DESC LIMIT 1) AS LatestHistoryType,
        -- Window function: Rank questions by score within their creation year
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM Q.CreationDate) ORDER BY Q.Score DESC, Q.ViewCount DESC) AS RankInYear,
        -- Complicated calculation: "Controversy" score based on score vs. explicit downvotes
        ABS(Q.Score - COALESCE((SELECT SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes AS V WHERE V.PostId = Q.Id), 0) * 2) AS ControversyScore
    FROM Posts AS Q
    WHERE Q.PostTypeId = 1 -- Only questions
      AND Q.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '5 years' -- Filter for recent questions
      AND Q.ViewCount > 100 -- Filter for sufficiently viewed questions
),
QuestionMetricsWithQuartileAvg AS (
    -- CTE 3: Joins QuestionMetricsBase with UserEngagement to add reputation quartile and calculate average score within that quartile.
    SELECT
        QMB.*,
        UE.ReputationQuartile,
        -- Window function: Average score of questions by users in the same reputation quartile
        AVG(QMB.QuestionScore) OVER (PARTITION BY UE.ReputationQuartile) AS AvgScoreInReputationQuartile
    FROM QuestionMetricsBase AS QMB
    INNER JOIN UserEngagement AS UE ON QMB.OwnerUserId = UE.UserId -- INNER JOIN here to ensure users have engagement stats
),
PostLinksDetailed AS (
    -- CTE 4: Extracts detailed information about post links (Linked/Duplicate).
    SELECT
        PL.PostId AS SourcePostId,
        PL.RelatedPostId AS TargetPostId,
        LT.Name AS LinkType,
        PL.CreationDate AS LinkCreationDate
    FROM PostLinks AS PL
    JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
    WHERE LT.Name IN ('Linked', 'Duplicate')
),
AllInvolvedPosts AS (
    -- CTE 5: Finds all unique post IDs that are involved in any link (either as source or target) using a set operator.
    SELECT SourcePostId AS PostId FROM PostLinksDetailed
    UNION
    SELECT TargetPostId AS PostId FROM PostLinksDetailed
),
LinkSummary AS (
    -- CTE 6: Summarizes incoming and outgoing links for all involved posts.
    SELECT
        AIP.PostId,
        COUNT(PLD_Out.SourcePostId) AS OutgoingLinks,
        COUNT(PLD_In.TargetPostId) AS IncomingLinks,
        MAX(PLD_Out.LinkCreationDate) AS LatestOutgoingLink,
        MAX(PLD_In.LinkCreationDate) AS LatestIncomingLink
    FROM AllInvolvedPosts AS AIP
    LEFT JOIN PostLinksDetailed AS PLD_Out ON AIP.PostId = PLD_Out.SourcePostId
    LEFT JOIN PostLinksDetailed AS PLD_In ON AIP.PostId = PLD_In.TargetPostId
    GROUP BY AIP.PostId
)
-- Main query: Combines all CTEs, applies further complex logic, and filters.
SELECT
    UE.DisplayName,
    UE.Reputation,
    UE.GoldBadges,
    UE.SilverBadges,
    QMWQA.Title AS QuestionTitle,
    QMWQA.QuestionCreationDate,
    QMWQA.QuestionScore,
    QMWQA.ViewCount,
    QMWQA.AnswerCount,
    QMWQA.FavoriteCount,
    QMWQA.AverageAnswerScore,
    QMWQA.ControversyScore,
    QMWQA.RankInYear,
    QMWQA.LatestHistoryType,
    COALESCE(LS.OutgoingLinks, 0) AS QuestionOutgoingLinks, -- NULL logic: COALESCE for links
    COALESCE(LS.IncomingLinks, 0) AS QuestionIncomingLinks,
    LS.LatestOutgoingLink,
    LS.LatestIncomingLink,
    ST.TagName AS PrimaryTag,
    ST.Count AS TagUseCount, -- Uses ST for tag count directly
    -- Complicated calculation: An engagement ratio combining user reputation, question views, scores, and answer counts.
    CAST(UE.Reputation AS DOUBLE PRECISION) / NULLIF(QMWQA.ViewCount + 1, 0) +
    CAST(QMWQA.QuestionScore AS DOUBLE PRECISION) / NULLIF(QMWQA.AnswerCount + 1, 0) +
    -- Correlated subquery: Calculates a user-specific comment activity score for the current question
    (SELECT COUNT(C2.Id) FROM Comments AS C2 WHERE C2.PostId = QMWQA.QuestionId AND C2.UserId = UE.UserId AND C2.Text IS NOT NULL) AS UserSpecificCommentActivityScore,
    -- String expression and NULL logic: Categorizes questions based on title content.
    COALESCE(
        CASE
            WHEN QMWQA.Title ILIKE '%SQL%' THEN 'Contains_SQL'
            WHEN QMWQA.Title ILIKE '%database%' THEN 'Contains_Database'
            WHEN QMWQA.Title ILIKE '%programming%' THEN 'Contains_Programming'
            ELSE 'Other_Topic'
        END, 'No_Title_Provided'
    ) AS TopicCategory,
    -- NULL logic: Checks if a question has ever been edited by a registered user.
    CASE
        WHEN P.LastEditorUserId IS NULL THEN 'Never_Edited'
        ELSE 'Edited_By_User'
    END AS EditStatus,
    -- Nested subquery with EXISTS: Checks if the question was closed as "off-topic".
    EXISTS (
        SELECT 1
        FROM PostHistory AS PH2
        WHERE PH2.PostId = QMWQA.QuestionId
          AND PH2.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
          AND PH2.Comment ILIKE '%off-topic%'
    ) AS WasClosedAsOffTopic,
    QMWQA.AvgScoreInReputationQuartile,
    -- Set operator and subquery in a CASE statement: Identifies "high contributors" based on highly viewed questions OR many badges.
    CASE
        WHEN UE.UserId IN (
            SELECT U_HighView.Id FROM Users U_HighView JOIN Posts P_HighView ON U_HighView.Id = P_HighView.OwnerUserId WHERE P_HighView.PostTypeId = 1 AND P_HighView.ViewCount > 5000
            UNION ALL -- Set operator: UNION ALL to combine two sets of user IDs
            SELECT U_ManyBadges.Id FROM Users U_ManyBadges JOIN Badges B_ManyBadges ON U_ManyBadges.Id = B_ManyBadges.UserId GROUP BY U_ManyBadges.Id HAVING COUNT(B_ManyBadges.Id) > 10
        ) THEN TRUE
        ELSE FALSE
    END AS IsHighContributor
FROM UserEngagement AS UE
INNER JOIN QuestionMetricsWithQuartileAvg AS QMWQA ON UE.UserId = QMWQA.OwnerUserId
LEFT JOIN LinkSummary AS LS ON QMWQA.QuestionId = LS.PostId -- Outer Join
LEFT JOIN Posts AS P ON QMWQA.QuestionId = P.Id -- Outer Join to get LastEditorUserId directly for the question
LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(QMWQA.Tags FROM 2 FOR LENGTH(QMWQA.Tags) - 2), '><')) AS TagName) AS TagList ON TRUE -- String expression: Parses tags
LEFT JOIN Tags AS ST ON TagList.TagName = ST.TagName -- Outer Join to get tag details
WHERE UE.TotalPosts > 5 -- Filter for users with sufficient posts
  AND QMWQA.AverageAnswerScore IS NOT NULL -- Exclude questions without any scored answers
  AND QMWQA.ControversyScore > 0 -- Only focus on questions with some 'controversy'
  AND (UE.TotalBadges >= 2 OR QMWQA.FavoriteCount > 0) -- Filter for users with some badges OR questions with favorites
  AND NOT EXISTS ( -- Correlated subquery with NULL logic: Exclude questions with recent 'spam' comments from registered users
        SELECT 1
        FROM Comments AS Comm
        WHERE Comm.PostId = QMWQA.QuestionId
          AND Comm.Text ILIKE '%spam%'
          AND Comm.CreationDate > QMWQA.QuestionCreationDate
          AND Comm.UserId IS NOT NULL
    )
GROUP BY
    UE.DisplayName, UE.Reputation, UE.GoldBadges, UE.SilverBadges,
    QMWQA.Title, QMWQA.QuestionCreationDate, QMWQA.QuestionScore, QMWQA.ViewCount,
    QMWQA.AnswerCount, QMWQA.FavoriteCount, QMWQA.AverageAnswerScore, QMWQA.ControversyScore,
    QMWQA.RankInYear, QMWQA.LatestHistoryType, LS.OutgoingLinks, LS.IncomingLinks,
    LS.LatestOutgoingLink, LS.LatestIncomingLink, ST.TagName, ST.Count, P.LastEditorUserId, QMWQA.QuestionId, UE.UserId,
    QMWQA.ViewCount, QMWQA.AnswerCount, QMWQA.AvgScoreInReputationQuartile, UE.ReputationQuartile
ORDER BY UE.Reputation DESC, QMWQA.QuestionScore DESC, QMWQA.QuestionCreationDate DESC
LIMIT 1000;
