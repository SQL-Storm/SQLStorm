-- {"query": "1573.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2677} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 3 WHEN B.Class = 2 THEN 2 WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BadgeClassScore,
        COALESCE(SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven,
        MAX(CASE WHEN V_Received.VoteTypeId = 3 AND V_Received.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '60 days') THEN 1 ELSE 0 END) AS HasRecentDownvoteOnTheirPosts,
        COUNT(DISTINCT P_Ans.Id) AS TotalAnswersPosted,
        COALESCE(AVG(P_Ans.Score), 0.0) AS AverageAnswerScore
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V_Given ON U.Id = V_Given.UserId AND V_Given.VoteTypeId IN (2, 3) -- Votes *given* by this user
    LEFT JOIN Posts P_Ans ON U.Id = P_Ans.OwnerUserId AND P_Ans.PostTypeId = 2 -- Answers *owned* by this user
    LEFT JOIN Votes V_Received ON P_Ans.Id = V_Received.PostId AND V_Received.VoteTypeId = 3 -- Downvotes *received* on their answers
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostContentMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.ParentId,
        P.CreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.ViewCount,
        P.Score,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        COALESCE(P.ClosedDate, '9999-12-31 23:59:59') AS ClosedOrFutureDate, -- Handle NULL ClosedDate
        DATE_PART('day', P.LastActivityDate - P.CreationDate) AS PostLifespanDays,
        LENGTH(P.Body) AS BodyLength,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS MajorEditCount, -- Edits to Title, Body, Tags
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6,8,9) THEN PH.CreationDate ELSE NULL END) AS LastContentEditHistoryDate,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id) AS DirectCommentCount -- Correlated subquery for comment count
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.ParentId, P.CreationDate, P.LastActivityDate, P.LastEditDate,
        P.ViewCount, P.Score, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.ClosedDate, P.Body
),
QuestionSummaries AS (
    SELECT
        PCM.PostId AS QuestionId,
        PCM.OwnerUserId AS QuestionOwnerId,
        PCM.CreationDate AS QuestionCreationDate,
        PCM.LastActivityDate AS QuestionLastActivityDate,
        PCM.ViewCount,
        PCM.Score AS QuestionScore,
        PCM.AnswerCount AS DeclaredAnswerCount,
        PCM.FavoriteCount,
        PCM.Title,
        PCM.Tags,
        PCM.ClosedOrFutureDate,
        PCM.PostLifespanDays,
        PCM.BodyLength AS QuestionBodyLength,
        PCM.DirectCommentCount AS QuestionDirectCommentCount,
        PCM.TotalHistoryEntries AS QuestionTotalHistoryEntries,
        PCM.UniqueEditors AS QuestionUniqueEditors,
        PCM.MajorEditCount AS QuestionMajorEditCount,
        PCM.LastContentEditHistoryDate,
        CASE
            WHEN PCM.ViewCount >= 10000 AND PCM.Score >= 50 AND PCM.AnswerCount >= 5 THEN 'Hot Topic - High Engagement'
            WHEN PCM.ViewCount >= 1000 AND PCM.Score >= 10 THEN 'Popular Question'
            WHEN PCM.PostLifespanDays < 30 AND PCM.ViewCount < 100 AND PCM.AnswerCount = 0 THEN 'New & Unanswered'
            WHEN PCM.ClosedDate IS NOT NULL AND PCM.ClosedDate <= CURRENT_TIMESTAMP THEN 'Closed Or Resolved'
            ELSE 'Standard'
        END AS QuestionEngagementCategory,
        COALESCE(STRING_AGG(T.TagName, '><' ORDER BY T.Count DESC), 'untagged') AS TopTagsString, -- String aggregation with ordering
        COUNT(DISTINCT T.TagName) AS NumberOfTags,
        SUM(T.Count) AS TotalTagPopularity
    FROM PostContentMetrics PCM
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(PCM.Tags FROM 2 FOR LENGTH(PCM.Tags)-2), '><')) AS TagNameExtracted ON PCM.Tags IS NOT NULL AND LENGTH(PCM.Tags) > 2
    LEFT JOIN Tags T ON T.TagName = TagNameExtracted
    WHERE PCM.PostTypeId = 1 -- Filter for Questions
    GROUP BY
        PCM.PostId, PCM.OwnerUserId, PCM.CreationDate, PCM.LastActivityDate, PCM.ViewCount, PCM.Score, PCM.AnswerCount,
        PCM.FavoriteCount, PCM.Title, PCM.Tags, PCM.ClosedOrFutureDate, PCM.PostLifespanDays, PCM.BodyLength,
        PCM.DirectCommentCount, PCM.TotalHistoryEntries, PCM.UniqueEditors, PCM.MajorEditCount, PCM.LastContentEditHistoryDate
),
AnswerAggregates AS (
    SELECT
        PCM.ParentId AS QuestionId,
        PCM.OwnerUserId AS AnswererId,
        UE.DisplayName AS AnswererDisplayName,
        COUNT(PCM.PostId) AS AnswersByThisUserToQuestion,
        SUM(PCM.Score) AS TotalScoreOnAnswers,
        AVG(PCM.Score) AS AverageScoreOnAnswers,
        SUM(PCM.BodyLength) AS TotalAnswerBodyLength,
        MAX(PCM.CreationDate) AS LastAnswerDate,
        COUNT(CASE WHEN PCM.Score >= 1 THEN 1 END) AS UpvotedAnswersCount,
        RANK() OVER (PARTITION BY PCM.ParentId ORDER BY SUM(PCM.Score) DESC, COUNT(PCM.PostId) DESC, MAX(PCM.CreationDate) DESC) AS AnswererRankForQuestion -- Window function for ranking answerers
    FROM PostContentMetrics PCM
    JOIN UserEngagement UE ON PCM.OwnerUserId = UE.UserId
    WHERE PCM.PostTypeId = 2 -- Filter for Answers
    GROUP BY PCM.ParentId, PCM.OwnerUserId, UE.DisplayName
)
SELECT
    QS.QuestionId,
    QS.Title,
    QS.QuestionCreationDate,
    QS.QuestionLastActivityDate,
    QS.QuestionLifespanDays,
    QS.ViewCount,
    QS.QuestionScore,
    QS.DeclaredAnswerCount,
    QS.FavoriteCount,
    QS.QuestionDirectCommentCount,
    QS.QuestionEngagementCategory,
    QS.TopTagsString,
    QS.NumberOfTags,
    QS.TotalTagPopularity,
    UE_Q.DisplayName AS QuestionOwnerDisplayName,
    UE_Q.Reputation AS QuestionOwnerReputation,
    UE_Q.TotalBadges AS QuestionOwnerTotalBadges,
    UE_Q.BadgeClassScore AS QuestionOwnerBadgeScore,
    QS.QuestionUniqueEditors,
    QS.MajorEditCount AS QuestionMajorContentEditCount,
    COALESCE(QS.LastContentEditHistoryDate, QS.QuestionCreationDate) AS EffectiveLastContentChangeDate, -- NULL logic with COALESCE
    AA.AnswererDisplayName AS TopAnswererName,
    AA.TotalScoreOnAnswers AS TopAnswererScoreOnQuestion,
    AA.AverageScoreOnAnswers AS TopAnswererAvgScoreOnQuestion,
    AA.AnswersByThisUserToQuestion,
    UE_A.Reputation AS TopAnswererReputation,
    UE_A.TotalBadges AS TopAnswererTotalBadges,
    UE_A.HasRecentDownvoteOnTheirPosts AS TopAnswererRecentDownvoteReceived, -- NULL logic (IS NULL or =0) in WHERE
    NTILE(4) OVER (ORDER BY QS.ViewCount DESC, QS.QuestionScore DESC, QS.FavoriteCount DESC) AS QuestionPopularityQuartile, -- NTILE window function
    LAG(QS.QuestionScore, 1, 0) OVER (PARTITION BY QS.QuestionOwnerId ORDER BY QS.QuestionCreationDate) AS PreviousQuestionScoreByOwner, -- LAG window function
    (QS.QuestionScore * 0.4 + QS.FavoriteCount * 0.3 + QS.QuestionDirectCommentCount * 0.2 + QS.MajorEditCount * 0.1) AS WeightedQuestionEngagementScore, -- Complex calculation
    NULLIF(QS.QuestionBodyLength, 0) AS NonZeroQuestionBodyLength, -- NULLIF example
    UPPER(SUBSTRING(QS.Title FROM 1 FOR 1)) AS FirstLetterOfTitle -- String expression
FROM QuestionSummaries QS
LEFT JOIN UserEngagement UE_Q ON QS.QuestionOwnerId = UE_Q.UserId
LEFT JOIN AnswerAggregates AA ON QS.QuestionId = AA.QuestionId AND AA.AnswererRankForQuestion = 1
LEFT JOIN UserEngagement UE_A ON AA.AnswererId = UE_A.UserId
WHERE
    QS.ViewCount > 250 -- Minimum view threshold
    AND QS.QuestionScore > 5 -- Minimum score threshold
    AND QS.DeclaredAnswerCount >= 1 -- Has at least one answer
    AND QS.PostLifespanDays > 14 -- Active for more than two weeks
    AND QS.QuestionMajorContentEditCount >= 1 -- Has seen at least one major content edit
    AND (UE_A.HasRecentDownvoteOnTheirPosts IS NULL OR UE_A.HasRecentDownvoteOnTheirPosts = 0) -- Top answerer has no recent downvotes on their posts OR there is no top answerer
    AND NOT EXISTS ( -- Correlated subquery for exclusion: filter out questions that are duplicates
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = QS.QuestionId
          AND PL.LinkTypeId = 3 -- Duplicate LinkType
    )
    AND QS.QuestionCreationDate BETWEEN (CURRENT_TIMESTAMP - INTERVAL '3 years') AND (CURRENT_TIMESTAMP - INTERVAL '6 months') -- Date range for activity
    AND QS.QuestionEngagementCategory NOT IN ('New & Unanswered', 'Closed Or Resolved') -- Exclude certain categories
ORDER BY
    WeightedQuestionEngagementScore DESC,
    QS.QuestionLastActivityDate DESC,
    QuestionPopularityQuartile
LIMIT 5000;
