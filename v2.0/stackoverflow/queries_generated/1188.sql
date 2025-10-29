-- {"query": "1188.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2882} 

WITH UserActivitySummary AS (
    -- Summarize user activity and general post engagement metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        U.CreationDate AS UserCreationDate,
        MAX(U.LastAccessDate) AS UserLastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalOwnedPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGiven,
        COALESCE(SUM(P.Score), 0) AS TotalOwnedPostScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) AS TotalQuestionViewsGenerated,
        MIN(P.CreationDate) AS FirstPostDate,
        MAX(P.CreationDate) AS LastPostDate,
        -- Calculate average score per post type for the user using window functions
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) OVER (PARTITION BY U.Id) AS AvgQuestionScorePerUser,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) OVER (PARTITION BY U.Id) AS AvgAnswerScorePerUser
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
),
HighQualityQuestionsWithHistory AS (
    -- Identify questions with specific high engagement criteria, significant edit history, and related comments
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.Title,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate AS QuestionLastActivityDate,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS BodyTitleTagEditCount, -- Specific edits to body, title, tags
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoreOnQuestion,
        COUNT(C.Id) AS TotalCommentsOnQuestion,
        -- Calculate the time difference in days between question creation and its accepted answer, if available
        DATE_PART('day', AGE(MAX(CASE WHEN A.Id = Q.AcceptedAnswerId THEN A.CreationDate ELSE NULL END), Q.CreationDate)) AS DaysToAcceptedAnswer,
        -- Correlated subquery: Check if the question owner has provided an answer to their own question
        EXISTS (
            SELECT 1
            FROM Posts AS SelfAnswer
            WHERE SelfAnswer.ParentId = Q.Id
              AND SelfAnswer.OwnerUserId = Q.OwnerUserId
              AND SelfAnswer.PostTypeId = 2
        ) AS HasSelfAnsweredQuestion,
        -- Extract the primary tag (first tag) from the question's tags string, handling NULLs gracefully
        COALESCE(
            (SELECT T.TagName FROM Tags T WHERE T.TagName = (string_to_array(substring(Q.Tags, 2, LENGTH(Q.Tags) - 2), '><'))[1]),
            'untagged'
        ) AS PrimaryTagOfQuestion,
        -- Window function to rank questions by score for each user
        ROW_NUMBER() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.CreationDate DESC) AS UserQuestionRankByScore
    FROM Posts AS Q
    LEFT JOIN PostHistory AS PH ON Q.Id = PH.PostId
    LEFT JOIN Comments AS C ON Q.Id = C.PostId
    LEFT JOIN Posts AS A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Join to answers to find accepted answer creation date
    WHERE Q.PostTypeId = 1 -- Only consider questions
      AND Q.Score >= 15 -- Minimum score threshold
      AND Q.ViewCount >= 2500 -- Minimum view count threshold
      AND Q.AnswerCount >= 3 -- At least three answers
      AND Q.ClosedDate IS NULL -- Ensure the question is not closed
      AND Q.CommunityOwnedDate IS NULL -- Ensure it's not community owned
    GROUP BY Q.Id, Q.OwnerUserId, Q.Title, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.CreationDate, Q.LastActivityDate, Q.Tags
    HAVING COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) >= 5 -- At least 5 edits to body, title, or tags
),
TopBadgesPerUser AS (
    -- Determine the highest class (Gold, then Silver, then Bronze) badge for each user
    SELECT
        B.UserId,
        B.Name AS TopBadgeName,
        B.Class AS TopBadgeClass, -- 1=Gold, 2=Silver, 3=Bronze
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Class ASC, B.Date DESC) AS rn
    FROM Badges AS B
)
-- Main query: Combines user activity, top questions, and badge information
SELECT
    UAS.DisplayName AS UserName,
    UAS.Reputation,
    UAS.TotalQuestionsAsked,
    UAS.TotalAnswersGiven,
    UAS.TotalOwnedPostScore,
    UAS.TotalQuestionViewsGenerated,
    UAS.AvgQuestionScorePerUser,
    UAS.AvgAnswerScorePerUser,
    HQ.QuestionId,
    HQ.Title AS TopQuestionTitle,
    HQ.QuestionScore,
    HQ.QuestionViewCount,
    HQ.QuestionAnswerCount,
    HQ.BodyTitleTagEditCount AS TopQuestionEditCount,
    HQ.DaysToAcceptedAnswer,
    HQ.HasSelfAnsweredQuestion,
    COALESCE(HQ.PrimaryTagOfQuestion, 'N/A') AS TopQuestionPrimaryTag,
    COALESCE(TBU.TopBadgeName, 'No Badges') AS HighestClassBadge,
    COALESCE(TBU.TopBadgeClass, 99) AS HighestBadgeClassCode, -- 99 for users with no badges
    -- String expression: Concatenate user's location and website URL, handling NULLs
    UPPER(COALESCE(Users.Location, 'Unknown Location')) || ' :: ' || COALESCE(Users.WebsiteUrl, 'No Website URL') AS UserContactInfo,
    -- Complex calculation: Ratio of UpVotes to DownVotes for the user, returning NULL if DownVotes are zero to prevent division by zero
    NULLIF(CAST(Users.UpVotes AS NUMERIC), 0) / NULLIF(CAST(Users.DownVotes AS NUMERIC), 0) AS UpVoteDownVoteRatio,
    -- Conditional expression: Categorize users into reputation tiers
    CASE
        WHEN UAS.Reputation >= 150000 THEN 'Legendary Contributor'
        WHEN UAS.Reputation >= 50000 THEN 'Distinguished Expert'
        WHEN UAS.Reputation >= 10000 THEN 'Experienced Member'
        WHEN UAS.Reputation >= 2000 THEN 'Active Participant'
        ELSE 'Emerging User'
    END AS ReputationTier,
    -- Scalar subquery to count posts by this user that contain external links (LinkTypeId = 1)
    (
        SELECT COUNT(DISTINCT PL.PostId)
        FROM PostLinks AS PL
        WHERE PL.PostId IN (SELECT P.Id FROM Posts P WHERE P.OwnerUserId = UAS.UserId)
          AND PL.LinkTypeId = 1 -- 'Linked' type indicates an outgoing link
    ) AS CountOfLinkedPostsByOwner
FROM UserActivitySummary AS UAS
JOIN Users ON UAS.UserId = Users.Id -- Re-join to Users table for additional user-specific columns not in UAS
LEFT JOIN HighQualityQuestionsWithHistory AS HQ ON UAS.UserId = HQ.OwnerUserId AND HQ.UserQuestionRankByScore = 1 -- Get the top-ranked question for each user
LEFT JOIN (SELECT UserId, TopBadgeName, TopBadgeClass FROM TopBadgesPerUser WHERE rn = 1) AS TBU ON UAS.UserId = TBU.UserId
WHERE UAS.TotalQuestionsAsked >= 5 -- Filter for users who have asked at least 5 questions
  AND UAS.TotalAnswersGiven >= 1 -- And have provided at least one answer
  AND UAS.Reputation > 750 -- Only consider more established users
  -- Correlated subquery in WHERE clause: Filter for users who have participated in at least 10 post history edits/rollbacks
  AND EXISTS (
      SELECT 1
      FROM PostHistory PH_Filter
      WHERE PH_Filter.UserId = UAS.UserId
        AND PH_Filter.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit or rollback of Title, Body, or Tags
      GROUP BY PH_Filter.UserId
      HAVING COUNT(PH_Filter.Id) > 10 -- User has made more than 10 such history entries
  )

UNION ALL -- Set operator to combine with another distinct set of users

-- Second part of the UNION ALL: Focus on users who are primarily answerers with many accepted answers
SELECT
    UAS.DisplayName AS UserName,
    UAS.Reputation,
    UAS.TotalQuestionsAsked,
    UAS.TotalAnswersGiven,
    UAS.TotalOwnedPostScore,
    UAS.TotalQuestionViewsGenerated,
    UAS.AvgQuestionScorePerUser,
    UAS.AvgAnswerScorePerUser,
    NULL AS QuestionId, -- N/A for this section
    'N/A - Answer-Focused User' AS TopQuestionTitle,
    NULL AS QuestionScore,
    NULL AS QuestionViewCount,
    NULL AS QuestionAnswerCount,
    NULL AS TopQuestionEditCount,
    NULL AS DaysToAcceptedAnswer,
    FALSE AS HasSelfAnsweredQuestion,
    'N/A' AS PrimaryTagOfQuestion,
    COALESCE(TBU.TopBadgeName, 'No Badges') AS HighestClassBadge,
    COALESCE(TBU.TopBadgeClass, 99) AS HighestBadgeClassCode,
    UPPER(COALESCE(Users.Location, 'Unknown Location')) || ' :: ' || COALESCE(Users.WebsiteUrl, 'No Website URL') AS UserContactInfo,
    NULLIF(CAST(Users.UpVotes AS NUMERIC), 0) / NULLIF(CAST(Users.DownVotes AS NUMERIC), 0) AS UpVoteDownVoteRatio,
    CASE
        WHEN UAS.Reputation >= 150000 THEN 'Legendary Contributor'
        WHEN UAS.Reputation >= 50000 THEN 'Distinguished Expert'
        WHEN UAS.Reputation >= 10000 THEN 'Experienced Member'
        WHEN UAS.Reputation >= 2000 THEN 'Active Participant'
        ELSE 'Emerging User'
    END AS ReputationTier,
    (
        SELECT COUNT(DISTINCT PL.PostId)
        FROM PostLinks AS PL
        WHERE PL.PostId IN (SELECT P.Id FROM Posts P WHERE P.OwnerUserId = UAS.UserId)
          AND PL.LinkTypeId = 1
    ) AS CountOfLinkedPostsByOwner
FROM UserActivitySummary AS UAS
JOIN Users ON UAS.UserId = Users.Id
LEFT JOIN (SELECT UserId, TopBadgeName, TopBadgeClass FROM TopBadgesPerUser WHERE rn = 1) AS TBU ON UAS.UserId = TBU.UserId
WHERE UAS.TotalAnswersGiven > UAS.TotalQuestionsAsked * 3 -- Users who answer significantly more than they ask
  AND UAS.Reputation > 2000
  -- Correlated subquery: Check if the user has provided at least 5 accepted answers
  AND (
      SELECT COUNT(AcceptedAnswers.Id)
      FROM Posts AcceptedAnswers
      WHERE AcceptedAnswers.OwnerUserId = UAS.UserId
        AND AcceptedAnswers.PostTypeId = 2 -- Must be an answer
        AND AcceptedAnswers.Id = (SELECT Q_Check.AcceptedAnswerId FROM Posts Q_Check WHERE Q_Check.Id = AcceptedAnswers.ParentId)
  ) >= 5
ORDER BY Reputation DESC, UserLastAccessDate DESC
LIMIT 150;
