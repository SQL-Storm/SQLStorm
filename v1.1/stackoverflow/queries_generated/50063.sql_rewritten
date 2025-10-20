-- {"query": "50063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 901} 
WITH TopTags AS (
    -- Step 1: Identify the 100 most frequently used tags.
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 100
),
TaggedQuestions AS (
    -- Step 2: Unnest tags for all questions and filter for those in our TopTags set.
    -- This creates a direct mapping from a question ID to a single top tag.
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS QuestionOwnerUserId,
        P.CreationDate AS QuestionDate,
        unnested.TagName
    FROM Posts AS P,
         unnest(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS unnested(TagName)
    WHERE P.PostTypeId = 1 AND unnested.TagName IN (SELECT TagName FROM TopTags)
),
UserTagActivity AS (
    -- Step 3: Aggregate user statistics for answers related to the tagged questions.
    -- We calculate total answers, average score, and total upvotes received per user per tag.
    SELECT
        A.OwnerUserId,
        TQ.TagName,
        COUNT(DISTINCT A.Id) AS AnswerCount,
        AVG(A.Score) AS AverageAnswerScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived
    FROM Posts AS A
    JOIN TaggedQuestions AS TQ ON A.ParentId = TQ.QuestionId
    LEFT JOIN Votes AS V ON A.Id = V.PostId
    WHERE A.PostTypeId = 2 AND A.OwnerUserId IS NOT NULL
    GROUP BY A.OwnerUserId, TQ.TagName
),
RankedUsersByTag AS (
    -- Step 4: Combine user activity with user and badge data, then rank users within each tag.
    -- The ranking is based on upvotes. We only consider users who have a gold badge for that specific tag.
    SELECT
        UTA.TagName,
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        UTA.AnswerCount,
        UTA.TotalUpvotesReceived,
        UTA.AverageAnswerScore,
        (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS TotalCommentsMade,
        B.Date AS GoldBadgeDate,
        ROW_NUMBER() OVER(PARTITION BY UTA.TagName ORDER BY UTA.TotalUpvotesReceived DESC, U.Reputation DESC) as Rank
    FROM UserTagActivity UTA
    JOIN Users U ON UTA.OwnerUserId = U.Id
    -- INNER JOIN to filter for only users who have earned the specific gold tag badge
    JOIN Badges B ON U.Id = B.UserId AND UTA.TagName = B.Name AND B.Class = 1 AND B.TagBased = '1'
    WHERE U.Reputation > 5000 AND UTA.AnswerCount >= 10 -- Filter for active, high-rep users
)
-- Final Step: Select the top 5 ranked users for each tag, including a correlated subquery
-- to find the time elapsed between them earning the gold badge and asking their first question in that tag.
SELECT
    RUT.TagName,
    RUT.Rank,
    RUT.DisplayName,
    RUT.Reputation,
    RUT.AnswerCount,
    RUT.TotalUpvotesReceived,
    RUT.TotalCommentsMade,
    ROUND(RUT.AverageAnswerScore, 2) AS AverageAnswerScore,
    (
        SELECT MIN(TQ.QuestionDate)
        FROM TaggedQuestions TQ
        WHERE TQ.QuestionOwnerUserId = RUT.UserId AND TQ.TagName = RUT.TagName
    ) AS FirstQuestionDateInTag,
    RUT.GoldBadgeDate
FROM RankedUsersByTag RUT
WHERE RUT.Rank <= 5
ORDER BY RUT.TagName, RUT.Rank;