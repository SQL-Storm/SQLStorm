-- {"query": "49070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1263} 

WITH RecentActivityPosts AS (
    -- Select posts that have been active or created within a relevant time window
    SELECT
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.CreationDate,
        P.LastActivityDate,
        P.Title,
        P.Tags
    FROM Posts P
    WHERE P.CreationDate >= (CURRENT_DATE - INTERVAL '5 years')
      AND P.LastActivityDate >= (CURRENT_DATE - INTERVAL '3 years')
),
HighQualityQuestions AS (
    -- Identify questions that meet specific quality and engagement criteria, and relate to 'sql' tag
    SELECT
        RAP.Id AS QuestionId,
        RAP.OwnerUserId AS QuestionOwnerId,
        RAP.Score AS QuestionScore,
        RAP.ViewCount,
        RAP.AnswerCount AS QuestionAnswerCount,
        RAP.FavoriteCount,
        RAP.AcceptedAnswerId,
        string_to_array(substring(RAP.Tags, 2, length(RAP.Tags)-2), '><') AS TagArray
    FROM RecentActivityPosts RAP
    WHERE RAP.PostTypeId = 1 -- Must be a question
      AND RAP.Score >= 10
      AND RAP.ViewCount >= 1000
      AND RAP.AnswerCount >= 2
      AND RAP.FavoriteCount >= 5
      AND RAP.Tags LIKE '%<sql>%' -- Filter for specific tag relevance
),
QuestionAndAnswers AS (
    -- Link high-quality questions with their respective answers
    SELECT
        HQ.QuestionId,
        HQ.QuestionOwnerId,
        HQ.QuestionScore,
        HQ.ViewCount,
        HQ.QuestionAnswerCount,
        HQ.FavoriteCount,
        HQ.AcceptedAnswerId,
        RAP_A.Id AS AnswerId,
        RAP_A.OwnerUserId AS AnswerOwnerId,
        RAP_A.Score AS AnswerScore
    FROM HighQualityQuestions HQ
    LEFT JOIN RecentActivityPosts RAP_A ON HQ.QuestionId = RAP_A.ParentId AND RAP_A.PostTypeId = 2
),
UserContributionScores AS (
    -- Calculate individual score components for various user activities related to high-quality content

    -- Score for owning high-quality questions
    SELECT
        HQ.QuestionOwnerId AS UserId,
        (HQ.QuestionScore * 2 + HQ.ViewCount / 100 + HQ.QuestionAnswerCount * 5 + HQ.FavoriteCount * 10) AS ScoreComponent
    FROM HighQualityQuestions HQ
    WHERE HQ.QuestionOwnerId IS NOT NULL

    UNION ALL

    -- Score for providing answers to high-quality questions, with bonus for accepted answers
    SELECT
        QAA.AnswerOwnerId AS UserId,
        (QAA.AnswerScore * 1.5 + CASE WHEN QAA.AcceptedAnswerId = QAA.AnswerId THEN 50 ELSE 0 END) AS ScoreComponent
    FROM QuestionAndAnswers QAA
    WHERE QAA.AnswerOwnerId IS NOT NULL AND QAA.AnswerId IS NOT NULL

    UNION ALL

    -- Score for commenting on high-quality questions or their answers
    SELECT
        C.UserId,
        1 AS ScoreComponent
    FROM Comments C
    INNER JOIN QuestionAndAnswers QAA ON C.PostId = QAA.QuestionId OR C.PostId = QAA.AnswerId
    WHERE C.UserId IS NOT NULL
      AND C.CreationDate >= (CURRENT_DATE - INTERVAL '5 years')

    UNION ALL

    -- Score for editing high-quality questions or their answers (including rollbacks as significant activity)
    SELECT
        PH.UserId,
        5 AS ScoreComponent
    FROM PostHistory PH
    INNER JOIN QuestionAndAnswers QAA ON PH.PostId = QAA.QuestionId OR PH.PostId = QAA.AnswerId
    WHERE PH.UserId IS NOT NULL
      AND PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit Title, Edit Body, Edit Tags, Rollback Title, Rollback Body, Rollback Tags
      AND PH.CreationDate >= (CURRENT_DATE - INTERVAL '5 years')

    UNION ALL

    -- Score for earning badges within the last 5 years, weighted by badge class
    SELECT
        B.UserId,
        CASE B.Class WHEN 1 THEN 100 WHEN 2 THEN 50 WHEN 3 THEN 10 ELSE 0 END AS ScoreComponent
    FROM Badges B
    WHERE B.Date >= (CURRENT_DATE - INTERVAL '5 years')
),
TotalUserScores AS (
    -- Aggregate all calculated score components for each user
    SELECT
        UCS.UserId,
        SUM(UCS.ScoreComponent) AS TotalScore
    FROM UserContributionScores UCS
    GROUP BY UCS.UserId
)
-- Final selection of top users, including their basic profile information and ranking
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes,
    U.DownVotes,
    TS.TotalScore,
    RANK() OVER (ORDER BY TS.TotalScore DESC, U.Reputation DESC, U.UpVotes DESC) AS OverallRank
FROM TotalUserScores TS
JOIN Users U ON TS.UserId = U.Id
WHERE U.Reputation > 100 -- Filter out users with very low reputation to focus on established contributors
ORDER BY OverallRank
LIMIT 100;
