-- {"query": "49018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1498} 
WITH UserPostSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) AS AveragePostScore,
        MAX(P.CreationDate) AS LatestPostDate
    FROM
        Users U
    JOIN
        Posts P ON U.Id = P.OwnerUserId
    WHERE
        P.PostTypeId IN (1, 2) -- Only questions and answers
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING
        COUNT(DISTINCT P.Id) > 10 -- Only consider users with more than 10 posts
),
UserVoteActivity AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(V.Id) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM
        Posts P
    JOIN
        Votes V ON P.Id = V.PostId
    WHERE
        V.VoteTypeId IN (1, 2) -- AcceptedByOriginator (1) or UpMod (2)
    GROUP BY
        P.OwnerUserId
    HAVING
        COUNT(V.Id) > 50 -- Only consider users with significant vote activity
),
UserTagMastery AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT T.TagName) AS DistinctTagsContributed,
        SUM(T.Count) AS TotalPopularTagCount -- Sum of popularity counts for tags associated with user's posts
    FROM
        Users U
    JOIN
        Posts P ON U.Id = P.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS PostTag -- Extracts individual tags from the 'Tags' string
    JOIN
        Tags T ON PostTag = T.TagName
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Ensure tags string is not empty or just "<>"
        AND T.Count > 1000 -- Only popular tags (arbitrary threshold)
    GROUP BY
        U.Id
    HAVING
        COUNT(DISTINCT T.TagName) > 5 -- At least 5 distinct popular tags
),
UserEditHistory AS (
    SELECT
        PH.UserId AS UserId,
        COUNT(PH.Id) AS TotalEdits,
        COUNT(DISTINCT PH.PostId) AS DistinctPostsEdited,
        MAX(PH.CreationDate) AS LatestEditDate
    FROM
        PostHistory PH
    WHERE
        PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24) -- Edit Title, Edit Body, Edit Tags, Rollback types, Suggested Edit Applied
        AND PH.UserId IS NOT NULL -- Exclude community edits if any
    GROUP BY
        PH.UserId
    HAVING
        COUNT(PH.Id) > 5 -- Only users with more than 5 edits
),
UserGoldBadges AS (
    SELECT
        B.UserId AS UserId,
        COUNT(B.Id) AS GoldBadgeCount
    FROM
        Badges B
    WHERE
        B.Class = 1 -- Gold badges
    GROUP BY
        B.UserId
    HAVING
        COUNT(B.Id) > 0 -- At least one gold badge
)
SELECT
    UPS.DisplayName,
    UPS.Reputation,
    UPS.TotalPosts,
    UPS.QuestionsAsked,
    UPS.AnswersProvided,
    COALESCE(UVA.TotalUpvotesReceived, 0) AS TotalUpvotesReceived,
    COALESCE(UVA.AcceptedAnswers, 0) AS AcceptedAnswers,
    COALESCE(UGT.DistinctTagsContributed, 0) AS DistinctTagsContributed,
    COALESCE(UGT.TotalPopularTagCount, 0) AS TotalPopularTagCount,
    COALESCE(UEH.TotalEdits, 0) AS TotalEdits,
    COALESCE(UEH.DistinctPostsEdited, 0) AS DistinctPostsEdited,
    COALESCE(UGB.GoldBadgeCount, 0) AS GoldBadgeCount,
    (
        UPS.TotalPostScore * 0.1 +                              -- Score from posts
        COALESCE(UVA.TotalUpvotesReceived, 0) * 0.5 +           -- Value upvotes highly
        COALESCE(UVA.AcceptedAnswers, 0) * 1.0 +                -- Extra for accepted answers
        COALESCE(UGT.TotalPopularTagCount, 0) * 0.0005 +        -- Contribution to popular tags (scaled, very high numbers)
        COALESCE(UGT.DistinctTagsContributed, 0) * 2 +          -- Diversity of tag contribution
        COALESCE(UEH.TotalEdits, 0) * 0.2 +                     -- Contribution from editing/improving posts
        COALESCE(UGB.GoldBadgeCount, 0) * 100 +                 -- High value for gold badges
        UPS.Reputation * 0.01                                   -- Direct reputation contribution
    ) AS CompositeUserScore
FROM
    UserPostSummary UPS
LEFT JOIN -- Use LEFT JOIN for vote activity as well, some users might not have many votes
    UserVoteActivity UVA ON UPS.UserId = UVA.UserId
LEFT JOIN -- Use LEFT JOIN for tag mastery, some active users might not contribute to popular tags
    UserTagMastery UGT ON UPS.UserId = UGT.UserId
LEFT JOIN -- Use LEFT JOIN for edit history, some active users might not edit much
    UserEditHistory UEH ON UPS.UserId = UEH.UserId
LEFT JOIN -- Use LEFT JOIN for badges, as not all active users might have gold badges
    UserGoldBadges UGB ON UPS.UserId = UGB.UserId
WHERE
    UPS.Reputation > 1000 -- Only consider users with a minimum reputation
ORDER BY
    CompositeUserScore DESC, UPS.Reputation DESC
LIMIT 100;